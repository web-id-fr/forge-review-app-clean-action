# Laravel Forge Review App Clean GitHub Action

Remove a deployed review-application on [Laravel Forge](https://forge.laravel.com) with GitHub action.

## Description

This action allows you to automatically delete a review-app site on a server managed by Forge when you close a pull-request.

It works in combination with this other action which removes create ad setup review-app site when you open a pull-request or push to a branch:
[web-id-fr/forge-review-app-action](https://github.com/web-id-fr/forge-review-app-action)

### Action running process

All steps are done using [Forge API](https://forge.laravel.com/api-documentation).

- Delete site.
- Delete database.

### Optional inputs variables

The action will determines the name of the site (host) and the database if they are not specified (which is **recommended**).

The `host` is based on the branch name (escaping it with only `a-z0-9-` chars) and the `root_domain`.

For example, a `fix-37` branch with `mydomain.tld` root_domain will result in a `fix-37.mydomain.tld` host.

`database_name` is also based on the branch name (escaping it with only `a-z0-9_` chars).

## Inputs

It is highly recommended that you store all inputs using [GitHub Secrets](https://docs.github.com/en/actions/reference/encrypted-secrets) or variables.

| Input                       | Required | Default                                | Description                                                                                                                                 |
|-----------------------------|----------|----------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------|
| `forge_api_token`           | yes      |                                        | Laravel Forge API key.<br>You can generate an API key in your [Forge dashboard](https://forge.laravel.com/user-profile/api).                |
| `forge_server_id`           | yes      |                                        | Laravel Forge server ID                                                                                                                     |
| `root_domain`               | no       |                                        | Root domain under which to create review-app site.                                                                                          |
| `host`                      | no       |                                        | Site host of the review-app.<br>The branch name the action is running on will be used to generate it if not defined (recommended).          |
| `prefix_with_pr_number`     | no       | `true`                                 | Use the pull-request number as host and database prefix when host is not manually defined.                                                  |
| `database_name`             | no       |                                        | Database name of the review-app site.<br>The branch name the action is running on will be used to generate it if not defined (recommended). |

## Outputs

| Output          | Description                                                          |
|-----------------|----------------------------------------------------------------------|
| `host`          | Host of the review-app (generated or forced one in inputs).          |
| `database_name` | Database name of the review-app (generated or forced one in inputs). |

## Examples

Delete a review-app on closed pull-requests:

```yml
name: review-app
on:
  pull_request:
    types: [ 'closed' ]

jobs:
  review-app:
    runs-on: ubuntu-latest
    name: "Delete Forge review-app"

    steps:
      - name: Clean review-app on Forge
        uses: web-id-fr/forge-review-app-clean-action@v1.0.0
        with:
          forge_api_token: ${{ secrets.FORGE_API_TOKEN }}
          forge_server_id: ${{ secrets.FORGE_SERVER_ID }}
```

## Credits

- [Ryan Gilles](https://www.linkedin.com/in/ryan-gilles-293680174/)

## License

The MIT License (MIT). Please see [License File](LICENSE.md) for more information.