# Laravel Forge Review App Clean GitHub Action

Remove a deployed review-application on [Laravel Forge](https://forge.laravel.com) with GitHub action.

## Inputs

It is highly recommended that you store all inputs using [GitHub Secrets](https://docs.github.com/en/actions/reference/encrypted-secrets) or variables.

| Input                       | Required | Default                                | Description                                                                                                                        |
|-----------------------------|----------|----------------------------------------|------------------------------------------------------------------------------------------------------------------------------------|
| `forge_api_token`           | yes      |                                        | Laravel Forge API key.<br>You can generate an API key in your [Forge dashboard](https://forge.laravel.com/user-profile/api).       |
| `forge_server_id`           | yes      |                                        | Laravel Forge server ID                                                                                                            |
| `root_domain`               | no       |                                        | Root domain under which to create review-app site.                                                                                 |
| `host`                      | no       |                                        | Site host of the review-app.<br>The branch name the action is running on will be used to generate it if not defined (recommended). |
| `database_name`             | no       |                                        | Database name of the review-app site (recommended).                                                                                |

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
      - name: Deploy
        uses: web-id-fr/forge-review-app-clean-action@v1.0.0
        with:
          forge_api_token: ${{ secrets.FORGE_API_TOKEN }}
          forge_server_id: ${{ secrets.FORGE_SERVER_ID }}
```

## Credits

- [Ryan Gilles](https://www.linkedin.com/in/ryan-gilles-293680174/)

## License

The MIT License (MIT). Please see [License File](LICENSE.md) for more information.