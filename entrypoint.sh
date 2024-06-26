#!/bin/sh
set -e

# Prepare vars and default values

if [[ -z "$INPUT_BRANCH" ]]; then
  INPUT_BRANCH=$GITHUB_HEAD_REF
fi

ESCAPED_BRANCH=$(echo "$INPUT_BRANCH" | sed -e 's/[^a-z0-9-]/-/g' | tr -s '-')

# Remove the trailing "-" character
if [[ $ESCAPED_BRANCH == *- ]]; then
    ESCAPED_BRANCH="${ESCAPED_BRANCH%-}"
fi

if [[ -z "$INPUT_PREFIX_WITH_PR_NUMBER" ]]; then
  INPUT_PREFIX_WITH_PR_NUMBER='true'
fi

if [[ $INPUT_PREFIX_WITH_PR_NUMBER == 'true' ]]; then
  if [[ -z "$INPUT_PR_NUMBER" ]]; then
    echo "* PR_NUMBER extraction from GITHUB_REF_NAME value: $GITHUB_REF_NAME"
    set +e
    PR_NUMBER=$(echo "$GITHUB_REF_NAME" | grep -oE '[0-9]+')
    set -e
    if [[ -z "$PR_NUMBER" ]]; then
      echo "Error: No PR number found"
      exit 1
    fi
  else
    echo "* PR_NUMBER manually defined to: $INPUT_PR_NUMBER"
    set +e
    PR_NUMBER=$(echo "$INPUT_PR_NUMBER" | grep -oE '[0-9]+')
    set -e
    if [[ -z "$PR_NUMBER" ]]; then
      echo "Error: No PR number found"
      exit 1
    fi
  fi
  echo "Parsed value: $PR_NUMBER"
  echo ""
  ESCAPED_BRANCH=$(echo "$PR_NUMBER-$ESCAPED_BRANCH")
fi

if [[ -z "$INPUT_HOST" ]]; then
  # Compute review-app host
  if [[ -z "$INPUT_ROOT_DOMAIN" ]]; then
    INPUT_HOST=$(echo "$ESCAPED_BRANCH")

    if [[ -n "$INPUT_FQDN_PREFIX" ]]; then
      INPUT_HOST=$(echo "$INPUT_FQDN_PREFIX$INPUT_HOST")
    fi

    # Limit to 64 chars max
    INPUT_HOST="${INPUT_HOST:0:64}"

    # Remove the trailing "-" character
    if [[ $INPUT_HOST == *- ]]; then
        INPUT_HOST="${INPUT_HOST%-}"
    fi
  else
    INPUT_HOST=$(echo "$ESCAPED_BRANCH.$INPUT_ROOT_DOMAIN")

    if [[ -n "$INPUT_FQDN_PREFIX" ]]; then
      INPUT_HOST=$(echo "$INPUT_FQDN_PREFIX$INPUT_HOST")
    fi

    # Limit to 64 chars max
    if [ ${#INPUT_HOST} -gt 64 ]; then
      INPUT_HOST=$(echo "${ESCAPED_BRANCH:0:$((${#ESCAPED_BRANCH} - $((${#INPUT_HOST} - 64))))}.$INPUT_ROOT_DOMAIN")
    fi

    # Remove dash in middle of the host
    if [[ $INPUT_HOST == *-.$INPUT_ROOT_DOMAIN ]]; then
        INPUT_HOST=$(echo $INPUT_HOST | sed "s/-\.$INPUT_ROOT_DOMAIN/\.$INPUT_ROOT_DOMAIN/")
    fi
  fi
fi

if [[ -n "$GITHUB_ACTIONS" && "$GITHUB_ACTIONS" == "true" ]]; then
  echo "host=$INPUT_HOST" >> $GITHUB_OUTPUT
fi

if [[ -z "$INPUT_DATABASE_NAME" ]]; then
  # Compute database name
  INPUT_DATABASE_NAME=$(echo "$ESCAPED_BRANCH" | sed -e 's/[^a-z0-9_]/_/g' | tr -s '_')
fi

if [[ -n "$INPUT_DATABASE_NAME_PREFIX" ]]; then
  INPUT_DATABASE_NAME=$(echo "$INPUT_DATABASE_NAME_PREFIX$INPUT_DATABASE_NAME")
fi

# Limit to 63 chars max
INPUT_DATABASE_NAME="${INPUT_DATABASE_NAME:0:63}"

if [[ -n "$GITHUB_ACTIONS" && "$GITHUB_ACTIONS" == "true" ]]; then
  echo "database_name=$INPUT_DATABASE_NAME" >> $GITHUB_OUTPUT
fi

AUTH_HEADER="Authorization: Bearer $INPUT_FORGE_API_TOKEN"

echo '* Get Forge server sites'
API_URL="https://forge.laravel.com/api/v1/servers/$INPUT_FORGE_SERVER_ID/sites"
JSON_RESPONSE=$(
  curl -s -H "$AUTH_HEADER" \
    -H "Accept: application/json" \
    "$API_URL"
)
echo "$JSON_RESPONSE" > sites.json

# Check if review-app site exists
SITE_DATA=$(jq -r '.sites[] | select(.name == "'"$INPUT_HOST"'") // empty' sites.json)
if [[ ! -z "$SITE_DATA" ]]; then
  echo "$SITE_DATA" > site.json
  SITE_ID=$(jq -r '.id' site.json)
  echo "A site (ID $SITE_ID) name match the host"
  RA_FOUND='true'
else
  echo "Site $INPUT_HOST not found"
  RA_FOUND='false'
fi

if [[ $RA_FOUND == 'true' ]]; then
  echo ""
  echo "* Delete review-app site"

  API_URL="https://forge.laravel.com/api/v1/servers/$INPUT_FORGE_SERVER_ID/sites/$SITE_ID"

  HTTP_STATUS=$(
    curl -s -o response.json -w "%{http_code}" \
      -X DELETE \
      -H "$AUTH_HEADER" \
      -H "Accept: application/json" \
      -H "Content-Type: application/json" \
      -d "$JSON_PAYLOAD" \
      "$API_URL"
  )

  JSON_RESPONSE=$(cat response.json)

  if [[ $HTTP_STATUS -eq 200 ]]; then
    echo "Site (ID $SITE_ID) deleted successfully"
  else
    echo "Failed to delete site (ID $SITE_ID). HTTP status code: $HTTP_STATUS"
    echo "JSON Response:"
    echo "$JSON_RESPONSE"
    exit 1
  fi
fi

echo ""
echo '* Get Forge server databases'
API_URL="https://forge.laravel.com/api/v1/servers/$INPUT_FORGE_SERVER_ID/databases"
JSON_RESPONSE=$(
  curl -s -H "$AUTH_HEADER" \
    -H "Accept: application/json" \
    "$API_URL"
)
echo "$JSON_RESPONSE" > databases.json

# Check if review-app database exists
DATABASE_DATA=$(jq -r '.databases[] | select(.name == "'"$INPUT_DATABASE_NAME"'") // empty' databases.json)
if [[ ! -z "$DATABASE_DATA" ]]; then
  echo "$DATABASE_DATA" > database.json
  DATABASE_ID=$(jq -r '.id' database.json)
  echo "A database (ID $DATABASE_ID, NAME $INPUT_DATABASE_NAME) name match the host"
  DATABASE_FOUND='true'
else
  echo "Database $INPUT_DATABASE_NAME not found"
  DATABASE_FOUND='false'
fi

if [[ $DATABASE_FOUND == 'true' ]]; then
  echo ""
  echo "* Delete review-app database"

  API_URL="https://forge.laravel.com/api/v1/servers/$INPUT_FORGE_SERVER_ID/databases/$DATABASE_ID"

  HTTP_STATUS=$(
    curl -s -o response.json -w "%{http_code}" \
      -X DELETE \
      -H "$AUTH_HEADER" \
      -H "Accept: application/json" \
      -H "Content-Type: application/json" \
      -d "$JSON_PAYLOAD" \
      "$API_URL"
  )

  JSON_RESPONSE=$(cat response.json)

  if [[ $HTTP_STATUS -eq 200 ]]; then
    echo $(jq '.site' response.json) > site.json
    SITE_ID=$(jq -r '.id' site.json)
    echo "Database (ID $DATABASE_ID, NAME $INPUT_DATABASE_NAME) deleted successfully"
  else
    echo "Failed to delete database (ID $SITE_ID, NAME $INPUT_DATABASE_NAME). HTTP status code: $HTTP_STATUS"
    echo "JSON Response:"
    echo "$JSON_RESPONSE"
    exit 1
  fi
fi
