#!/bin/bash
set -e

AUTH_HEADER="Authorization: Bearer $INPUT_FORGE_API_TOKEN"
ACCEPT_HEADER="Accept: application/vnd.api+json"
API_BASE="https://forge.laravel.com/api/orgs/$INPUT_FORGE_ORGANIZATION/servers/$INPUT_FORGE_SERVER_ID"

# Delete a Forge site by exact host name, if it exists.
# Sets SITE_STATUS to 'deleted' / 'not_found' / 'error' (does not exit on API
# failure: callers decide whether that's fatal, see run_classic_mode vs
# run_cleanup_orphans_mode).
delete_site() {
  local HOST="$1"
  local API_URL JSON_RESPONSE SITE_DATA SITE_ID HTTP_STATUS

  API_URL="$API_BASE/sites?filter%5Bname%5D=$HOST"
  JSON_RESPONSE=$(curl -s -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" "$API_URL")
  echo "$JSON_RESPONSE" > sites.json

  # Check if review-app site exists (filter[name] may be a partial match, so confirm the exact name)
  SITE_DATA=$(jq -r '.data[] | select(.attributes.name == "'"$HOST"'") // empty' sites.json)
  if [[ -z "$SITE_DATA" ]]; then
    echo "Site $HOST not found"
    SITE_STATUS='not_found'
    return
  fi

  echo "$SITE_DATA" > site.json
  SITE_ID=$(jq -r '.id' site.json)
  echo "A site (ID $SITE_ID) name match the host"

  echo ""
  echo "* Delete review-app site"

  API_URL="$API_BASE/sites/$SITE_ID"
  HTTP_STATUS=$(
    curl -s -o response.json -w "%{http_code}" \
      -X DELETE \
      -H "$AUTH_HEADER" \
      -H "$ACCEPT_HEADER" \
      "$API_URL"
  )
  JSON_RESPONSE=$(cat response.json)

  if [[ $HTTP_STATUS -eq 202 ]]; then
    echo "Site (ID $SITE_ID) deleted successfully"
    SITE_STATUS='deleted'
  else
    echo "Failed to delete site (ID $SITE_ID). HTTP status code: $HTTP_STATUS"
    echo "JSON Response:"
    echo "$JSON_RESPONSE"
    SITE_STATUS='error'
  fi
}

# Delete a Forge database schema by exact name, if it exists.
# Sets DATABASE_STATUS to 'deleted' / 'not_found' / 'error' (does not exit on
# API failure: callers decide whether that's fatal).
delete_database() {
  local DB_NAME="$1"
  local API_URL JSON_RESPONSE DATABASE_DATA DATABASE_ID HTTP_STATUS

  echo ""
  echo '* Get Forge server databases'
  API_URL="$API_BASE/database/schemas?filter%5Bname%5D=$DB_NAME"
  JSON_RESPONSE=$(curl -s -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" "$API_URL")
  echo "$JSON_RESPONSE" > databases.json

  # Check if review-app database exists (filter[name] may be a partial match, so confirm the exact name)
  DATABASE_DATA=$(jq -r '.data[] | select(.attributes.name == "'"$DB_NAME"'") // empty' databases.json)
  if [[ -z "$DATABASE_DATA" ]]; then
    echo "Database $DB_NAME not found"
    DATABASE_STATUS='not_found'
    return
  fi

  echo "$DATABASE_DATA" > database.json
  DATABASE_ID=$(jq -r '.id' database.json)
  echo "A database (ID $DATABASE_ID, NAME $DB_NAME) name match the host"

  echo ""
  echo "* Delete review-app database"

  API_URL="$API_BASE/database/schemas/$DATABASE_ID"
  HTTP_STATUS=$(
    curl -s -o response.json -w "%{http_code}" \
      -X DELETE \
      -H "$AUTH_HEADER" \
      -H "$ACCEPT_HEADER" \
      "$API_URL"
  )
  JSON_RESPONSE=$(cat response.json)

  if [[ $HTTP_STATUS -eq 202 ]]; then
    echo "Database (ID $DATABASE_ID, NAME $DB_NAME) deleted successfully"
    DATABASE_STATUS='deleted'
  else
    echo "Failed to delete database (ID $DATABASE_ID, NAME $DB_NAME). HTTP status code: $HTTP_STATUS"
    echo "JSON Response:"
    echo "$JSON_RESPONSE"
    DATABASE_STATUS='error'
  fi
}

run_classic_mode() {
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

  echo '* Get Forge server sites'
  delete_site "$INPUT_HOST"
  if [[ "$SITE_STATUS" == 'error' ]]; then
    exit 1
  fi

  echo ""
  delete_database "$INPUT_DATABASE_NAME"
  if [[ "$DATABASE_STATUS" == 'error' ]]; then
    exit 1
  fi
}

# List every site on the Forge server, following JSON:API pagination (links.next).
# Writes the full JSON array of site objects to $1.
list_all_sites() {
  OUTPUT_FILE="$1"
  API_URL="$API_BASE/sites"
  echo '[]' > "$OUTPUT_FILE"

  while [[ -n "$API_URL" && "$API_URL" != "null" ]]; do
    JSON_RESPONSE=$(curl -s -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" "$API_URL")
    echo "$JSON_RESPONSE" | jq '.data' > page.json
    jq -s '.[0] + .[1]' "$OUTPUT_FILE" page.json > merged.json
    mv merged.json "$OUTPUT_FILE"
    API_URL=$(echo "$JSON_RESPONSE" | jq -r '.links.next // empty')
  done
}

# Derive the review-app database name from its host the same way the classic
# mode would have generated it from the branch name, since the branch name
# itself is not available in discovery mode.
# NB: this does not account for a custom fqdn_prefix, which is not
# recoverable from the host alone.
derive_database_name_from_host() {
  local HOST="$1"
  local SEGMENT DB_NAME
  SEGMENT="$HOST"
  if [[ -n "$INPUT_ROOT_DOMAIN" && "$HOST" == *".$INPUT_ROOT_DOMAIN" ]]; then
    SEGMENT="${HOST%.$INPUT_ROOT_DOMAIN}"
  fi
  DB_NAME=$(echo "$SEGMENT" | sed -e 's/[^a-z0-9_]/_/g' | tr -s '_')
  if [[ -n "$INPUT_DATABASE_NAME_PREFIX" ]]; then
    DB_NAME=$(echo "$INPUT_DATABASE_NAME_PREFIX$DB_NAME")
  fi
  echo "${DB_NAME:0:63}"
}

# Check the state of a GitHub PR.
# Echoes one of: open | closed | not_found | unknown (API error/rate-limit: treat as "don't touch").
check_pr_state() {
  local PR_NUMBER="$1"
  local GH_URL HTTP_STATUS STATE

  GH_URL="https://api.github.com/repos/$EFFECTIVE_REPOSITORY/pulls/$PR_NUMBER"
  HTTP_STATUS=$(
    curl -s -o pr_response.json -w "%{http_code}" \
      -H "Authorization: Bearer $INPUT_GITHUB_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      "$GH_URL"
  )

  if [[ $HTTP_STATUS -eq 200 ]]; then
    STATE=$(jq -r '.state // empty' pr_response.json)
    if [[ "$STATE" == "open" ]]; then
      echo "open"
    else
      echo "closed"
    fi
  elif [[ $HTTP_STATUS -eq 404 ]]; then
    echo "not_found"
  else
    echo "unknown"
  fi
}

run_cleanup_orphans_mode() {
  if [[ -z "$INPUT_GITHUB_TOKEN" ]]; then
    echo "Error: 'github_token' input is required when 'cleanup_orphans' is true"
    exit 1
  fi

  EFFECTIVE_REPOSITORY="$INPUT_REPOSITORY"
  if [[ -z "$EFFECTIVE_REPOSITORY" ]]; then
    EFFECTIVE_REPOSITORY="$GITHUB_REPOSITORY"
  fi
  if [[ -z "$EFFECTIVE_REPOSITORY" ]]; then
    echo "Error: 'repository' input is required when 'cleanup_orphans' is true (and GITHUB_REPOSITORY is not set)"
    exit 1
  fi

  EFFECTIVE_HOST_PATTERN="$INPUT_HOST_PATTERN"
  if [[ -z "$EFFECTIVE_HOST_PATTERN" ]]; then
    if [[ -z "$INPUT_ROOT_DOMAIN" ]]; then
      echo "Error: either 'host_pattern' or 'root_domain' input is required when 'cleanup_orphans' is true"
      exit 1
    fi
    ESCAPED_ROOT_DOMAIN=$(echo "$INPUT_ROOT_DOMAIN" | sed -e 's/\./\\./g')
    EFFECTIVE_HOST_PATTERN="^[0-9]+-.*\.${ESCAPED_ROOT_DOMAIN}\$"
  fi

  echo "* Repository: $EFFECTIVE_REPOSITORY"
  echo "* Host pattern: $EFFECTIVE_HOST_PATTERN"
  echo "* Dry run: ${INPUT_DRY_RUN:-false}"
  echo ""

  echo '* Get Forge server sites (paginated)'
  list_all_sites all_sites.json
  TOTAL_SITES=$(jq 'length' all_sites.json)
  echo "Found $TOTAL_SITES site(s) on the server"

  echo ""
  echo '* Filter sites matching host_pattern and extract PR number'
  jq --arg pat "$EFFECTIVE_HOST_PATTERN" '
    [.[] | select(.attributes.name | test($pat))
         | {id: .id, host: .attributes.name}]
  ' all_sites.json > matched_sites.json
  MATCHED_COUNT=$(jq 'length' matched_sites.json)

  # A matched host may still not start with a PR number, e.g. with a custom
  # host_pattern that does not anchor on it. Such sites can never be resolved
  # to a PR, so make that visible instead of silently dropping them.
  jq '[.[] | select(.host | test("^[0-9]+-") | not)]' matched_sites.json > unparsable_sites.json
  UNPARSABLE_COUNT=$(jq 'length' unparsable_sites.json)
  if [[ $UNPARSABLE_COUNT -gt 0 ]]; then
    echo "Warning: $UNPARSABLE_COUNT of $MATCHED_COUNT matched site(s) do not start with a PR number ({pr}-...) and will be ignored (they can never be cleaned up by this action):"
    jq -r '.[].host' unparsable_sites.json | sed 's/^/  - /'
  fi

  # Extract the PR number (leading digits) from each parsable host, then
  # dedup by PR number (keep first occurrence).
  jq '[.[] | select(.host | test("^[0-9]+-"))]' matched_sites.json > parsable_sites.json
  jq '
    [.[] | . + {pr: (.host | capture("^(?<pr>[0-9]+)-").pr)}]
    | unique_by(.pr)
  ' parsable_sites.json > candidates.json

  CANDIDATE_COUNT=$(jq 'length' candidates.json)
  echo "Found $CANDIDATE_COUNT candidate review-app(s) after filtering/dedup"

  ORPHANS_FOUND=0
  ORPHANS_DELETED=0
  echo '[]' > orphans.json

  append_orphan_result() {
    local PR="$1" HOST="$2" DELETED="$3"
    jq --arg pr "$PR" --arg host "$HOST" --argjson deleted "$DELETED" \
      '. + [{pr: $pr, host: $host, deleted: $deleted}]' orphans.json > orphans.json.tmp
    mv orphans.json.tmp orphans.json
  }

  for i in $(seq 0 $((CANDIDATE_COUNT - 1))); do
    CANDIDATE=$(jq -c ".[$i]" candidates.json)
    CANDIDATE_PR=$(echo "$CANDIDATE" | jq -r '.pr')
    CANDIDATE_HOST=$(echo "$CANDIDATE" | jq -r '.host')

    echo ""
    echo "* Checking PR #$CANDIDATE_PR (site: $CANDIDATE_HOST)"
    PR_STATE=$(check_pr_state "$CANDIDATE_PR")

    if [[ "$PR_STATE" == "open" ]]; then
      echo "PR #$CANDIDATE_PR is open, skipping (not orphaned)"
      continue
    fi

    if [[ "$PR_STATE" == "unknown" ]]; then
      echo "Warning: could not reliably determine PR #$CANDIDATE_PR state (API error/rate-limit). Skipping site to be safe, it will be re-checked on the next run."
      continue
    fi

    # PR_STATE is "closed" or "not_found": confirmed orphan
    echo "PR #$CANDIDATE_PR is $PR_STATE, site $CANDIDATE_HOST is orphaned"
    ORPHANS_FOUND=$((ORPHANS_FOUND + 1))

    if [[ "${INPUT_DRY_RUN:-false}" == 'true' ]]; then
      echo "[dry_run] Would delete site $CANDIDATE_HOST (and its database)"
      append_orphan_result "$CANDIDATE_PR" "$CANDIDATE_HOST" 'false'
      continue
    fi

    delete_site "$CANDIDATE_HOST"
    if [[ "$SITE_STATUS" == 'error' ]]; then
      echo "Warning: failed to delete site $CANDIDATE_HOST, skipping this candidate for now (it will be retried on the next run)"
      append_orphan_result "$CANDIDATE_PR" "$CANDIDATE_HOST" 'false'
      continue
    fi

    DB_NAME=$(derive_database_name_from_host "$CANDIDATE_HOST")
    delete_database "$DB_NAME"
    if [[ "$DATABASE_STATUS" == 'error' ]]; then
      echo "Warning: site $CANDIDATE_HOST was deleted but failed to delete database $DB_NAME, skipping the rest of this candidate for now (it will be retried on the next run)"
      append_orphan_result "$CANDIDATE_PR" "$CANDIDATE_HOST" 'false'
      continue
    fi

    ORPHANS_DELETED=$((ORPHANS_DELETED + 1))
    append_orphan_result "$CANDIDATE_PR" "$CANDIDATE_HOST" 'true'
  done

  echo ""
  echo "* Summary: $ORPHANS_FOUND orphan(s) found, $ORPHANS_DELETED deleted"

  if [[ -n "$GITHUB_ACTIONS" && "$GITHUB_ACTIONS" == "true" ]]; then
    echo "host=" >> $GITHUB_OUTPUT
    echo "database_name=" >> $GITHUB_OUTPUT
    echo "orphans_found=$ORPHANS_FOUND" >> $GITHUB_OUTPUT
    echo "orphans_deleted=$ORPHANS_DELETED" >> $GITHUB_OUTPUT
    echo "orphans_json=$(jq -c '.' orphans.json)" >> $GITHUB_OUTPUT
  fi
}

if [[ "$INPUT_CLEANUP_ORPHANS" == 'true' ]]; then
  run_cleanup_orphans_mode
else
  run_classic_mode
fi
