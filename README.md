# Laravel Forge Review App Clean GitHub Action

Remove a deployed review-application on [Laravel Forge](https://forge.laravel.com) with GitHub action.

## Description

This action allows you to automatically delete a review-app site on a server managed by Forge when you close a pull-request.

It works in combination with this other action which removes create ad setup review-app site when you open a pull-request or push to a branch:
[web-id-fr/forge-review-app-action](https://github.com/web-id-fr/forge-review-app-action)

### Action running process

All steps are done using the [Forge API v2](https://forge.laravel.com/docs/api-reference/introduction).

- Delete site.
- Delete database.

### Optional inputs variables

The action will determines the name of the site (host) and the database if they are not specified (which is **recommended**).

The `host` is based on the branch name (escaping it with only `a-z0-9-` chars) and the `root_domain`.

For example, a `fix-37` branch with `mydomain.tld` root_domain will result in a `fix-37.mydomain.tld` host.

`database_name` is also based on the branch name (escaping it with only `a-z0-9_` chars).

## Upgrading to v2

Starting with `v2`, this action uses [Forge API v2](https://forge.laravel.com/docs/api-reference/introduction), which is organized around organizations and servers instead of a flat list of servers as in v1. This is a breaking change if you are currently using `@v1` (or a `v1.x` tag).

### What you need to change in your workflow

1. **Pin the action to `@v2`** instead of `@v1` (or a `v1.x` tag). `@v1` keeps working against the previous behavior for existing consumers, it will not receive the v2 changes.
2. **Add the new required input `forge_organization`**, set to the slug of the organization that owns your server (visible in the Forge dashboard URL when browsing your server).
3. Regenerate/verify your `forge_api_token` still has access to the organization and server you are targeting.

Everything else (inputs, outputs, host/database name generation) keeps working the same way.

## API token & scopes

The Forge API v2 uses OAuth2-style scopes on API tokens (unlike the v1 legacy tokens, which were unscoped and granted full access to everything the owning account could do). When generating your `forge_api_token` in the [Forge dashboard](https://forge.laravel.com/user-profile/api), select the following scopes so this action can run end-to-end:

The order below matches the order scopes appear in the Forge dashboard's token creation form (server scopes first, then site scopes), to make them easier to tick off:

| Scope                     | Why it's needed                                        |
|---------------------------|---------------------------------------------------------|
| `server:view`              | List sites and database schemas to find the review-app. |
| `server:delete-databases`  | Delete the review-app database.                          |
| `site:delete`              | Delete the review-app site.                              |

Also make sure the token owner has access to the target organization and server.

## Inputs

It is highly recommended that you store all inputs using [GitHub Secrets](https://docs.github.com/en/actions/reference/encrypted-secrets) or variables.

| Input                   | Required | Default | Description                                                                                                                                                                                   |
|-------------------------|----------|---------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `forge_api_token`       | yes      |         | Laravel Forge API key.<br>You can generate an API key in your [Forge dashboard](https://forge.laravel.com/user-profile/api).                                                                  |
| `forge_organization`    | yes      |         | Laravel Forge organization slug (required by the [API v2](https://forge.laravel.com/docs/api-reference/introduction)).                                                                       |
| `forge_server_id`       | yes      |         | Laravel Forge server ID                                                                                                                                                                       |
| `root_domain`           | no       |         | Root domain under which to create review-app site.                                                                                                                                            |
| `host`                  | no       |         | Site host of the review-app.<br>The branch name the action is running on will be used to generate it if not defined (recommended).                                                            |
| `prefix_with_pr_number` | no       | `true`  | Use the pull-request number as host and database prefix when host is not manually defined.                                                                                                    |
| `fqdn_prefix`           | no       |         | Prefix the whole FQDN (e.g.: "app.")                                                                                                                                                          |
| `pr_number`             | no       |         | Manually define pull-request number (⚠️ Based on `GITHUB_REF_NAME` by default, but does not seems to work properly, according to this [issue](https://github.com/actions/runner/issues/256)). |
| `database_name`         | no       |         | Database name of the review-app site.<br>The branch name the action is running on will be used to generate it if not defined (recommended).                                                   |
| `database_name_prefix`  | no       |         | Database name prefix, useful for PostgreSQL that does not support digits (PR number) for first chars.                                                                                         |
| `cleanup_orphans`       | no       | `false` | Enable "orphan cleanup" mode (see below): instead of deleting a single, precisely-identified review-app, discover and delete every review-app on the server whose PR is no longer open.        |
| `repository`            | no (required if `cleanup_orphans: true`) | `$GITHUB_REPOSITORY` | GitHub repository (`owner/repo`) to check PR state against.                                                                                                            |
| `github_token`          | no (required if `cleanup_orphans: true`) |  | GitHub token used to check PR state (`repos/{repository}/pulls/{pr}`). Read access to pull requests is enough.                                                                       |
| `host_pattern`          | no       | derived from `root_domain`: `^[0-9]+-.*\.{root_domain}$` | ERE regex (`jq`/`grep -P` compatible) used to identify review-app sites among all sites on the server. Override if your naming scheme differs from `{pr}-{branch}.{root_domain}`. |
| `dry_run`               | no       | `false` | If `true` (in `cleanup_orphans` mode), only log the orphaned sites that would be deleted, without deleting anything. Useful for a first verification run.                                     |

## Outputs

| Output            | Description                                                                                                      |
|-------------------|--------------------------------------------------------------------------------------------------------------------|
| `host`            | Host of the review-app (generated or forced one in inputs). Empty in `cleanup_orphans` mode.                     |
| `database_name`   | Database name of the review-app (generated or forced one in inputs). Empty in `cleanup_orphans` mode.            |
| `orphans_found`   | Number of orphaned review-apps detected (`cleanup_orphans` mode only).                                           |
| `orphans_deleted` | Number of orphaned review-apps actually deleted (`cleanup_orphans` mode only, always `0` if `dry_run: true`).    |
| `orphans_json`    | JSON array of the orphaned sites processed, e.g. `[{"pr": "1234", "host": "1234-fix-bug.example.com", "deleted": true}]` (`cleanup_orphans` mode only). |

## Orphan cleanup mode

The default mode (documented above) deletes **one** review-app, reacting to a single PR event (`closed`, `unlabeled`). If that triggering event is ever missed (cancelled run, disabled workflow, label removed then PR closed outside GitHub Actions...), the review-app is left orphaned on the Forge server forever, since nothing re-triggers the missed event.

`cleanup_orphans: true` switches the action to a periodic, self-healing mode instead: it lists every site on the Forge server, filters the ones that look like review-apps (`host_pattern`), checks the state of their associated PR via the GitHub API, and deletes the ones whose PR is no longer open (closed, merged, or deleted).

To stay safe by default: a site is only ever deleted when the PR's state is confirmed as not open. If the GitHub API call fails or is rate-limited, the site is **skipped** (not deleted) — it will simply be re-checked on the next scheduled run.

This is entirely opt-in and additive: when `cleanup_orphans` is absent or `false`, the action behaves exactly as before, with the same inputs/outputs.

Typical usage, on a schedule:

```yml
name: review-app-force-clean
on:
  schedule:
    - cron: '0 3 * * *'
  workflow_dispatch:

jobs:
  cleanup-orphans:
    runs-on: ubuntu-latest
    name: "Clean orphaned Forge review-apps"

    steps:
      - name: Clean orphaned review-apps on Forge
        uses: web-id-fr/forge-review-app-clean-action@v2
        with:
          cleanup_orphans: 'true'
          forge_api_token: ${{ secrets.FORGE_API_TOKEN }}
          forge_organization: ${{ secrets.FORGE_ORGANIZATION }}
          forge_server_id: ${{ secrets.FORGE_SERVER_ID }}
          root_domain: myapp.example.com
          github_token: ${{ secrets.GITHUB_TOKEN }}
          dry_run: 'false'
```

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
        uses: web-id-fr/forge-review-app-clean-action@v2.0.0
        with:
          forge_api_token: ${{ secrets.FORGE_API_TOKEN }}
          forge_organization: ${{ secrets.FORGE_ORGANIZATION }}
          forge_server_id: ${{ secrets.FORGE_SERVER_ID }}
```

## Credits

- [Ryan Gilles](https://www.linkedin.com/in/ryan-gilles-293680174/)

## License

The MIT License (MIT). Please see [License File](LICENSE.md) for more information.