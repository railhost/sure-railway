# Sure on Railway

Run [Sure](https://github.com/we-promise/sure), the open-source personal finance app (a community fork of Maybe), on Railway with Postgres and Redis. Track bank accounts, budgets, investments and net worth in one place, on a server only you control.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/FVYvkk?utm_medium=integration&utm_source=template&utm_campaign=sure)

## What you get

- The official Sure image, pinned to a tested stable release.
- Postgres and Redis on a private network, each with its own volume.
- Signup closed from the first boot. Sure creates your account from `ADMIN_EMAIL` and a generated password, so a stranger can't claim the instance.
- The web app and the background worker in one service, sharing one volume for uploads. Imports, exports and statements work without outside storage.
- Daily checks for new Sure releases. Each one is smoke-tested before it reaches you.

## After deploying

1. Open the Sure service's public URL.
2. Log in with `ADMIN_EMAIL` and `ADMIN_PASSWORD` from the service's **Variables** tab. The password was generated for you.
3. Fill in your name, country and currency. Sure then shows your dashboard.
4. Add an account by hand, import a CSV, or connect a bank under **Settings → Bank sync**.

To invite family members, use **Settings → Profile Info**. To let anyone sign up, open **Settings → Self-Hosting** and change the onboarding setting. Leave it closed on a public URL.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `ADMIN_EMAIL` | you fill it in | Login for the first user, created on the first boot |
| `ADMIN_PASSWORD` | generated | Password for the first user. Change it at `/password/edit` after you log in |
| `SECRET_KEY_BASE` | generated | Signs sessions and encrypts saved bank credentials. Never change it, or saved credentials become unreadable |
| `DB_HOST`, `DB_PORT`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` | Postgres service | Database connection |
| `REDIS_URL` | Redis service | Queue for background jobs |
| `APP_DOMAIN` | `${{RAILWAY_PUBLIC_DOMAIN}}` | Domain used in links in emails. Change it if you add your own domain |
| `OPENAI_ACCESS_TOKEN` | empty | Optional. Turns on the AI chat and automatic categories. You pay OpenAI for what you use |

`ADMIN_EMAIL` and `ADMIN_PASSWORD` only matter until the first user exists. After that, change your login inside Sure.

Sure reads many more variables: email (`SMTP_*`), bank providers, OpenID Connect login, S3 storage and more. See [Sure's docs](https://github.com/we-promise/sure/tree/main/docs/hosting). Add them to the Sure service when you need them. Public networking should point at port `8080`, the port Railway gives the service by default.

## Storage

- Postgres keeps all your financial data on its volume.
- Redis keeps the job queue on its volume.
- Sure's volume is mounted at `/rails/storage`. Profile photos, imported files, statements and exports live there. Keep the volume.

## Why one service runs both the web app and the worker

Sure's worker (Sidekiq) reads the files you upload: CSV imports, PDF statements, exports. Railway can't share a volume between two services, so a separate worker service could not see them. The entrypoint runs the web server and the worker side by side in one container. If either stops, the container exits and Railway restarts it.

The service uses about 700 MB of memory at rest. Plan for 1 GB.

## Updates

The template follows Sure's stable releases and skips its alpha pre-releases. A GitHub Action checks for a new release once a day, builds it and runs the smoke test (`scripts/smoke-test.sh`). Only releases that pass are merged. Failures open an issue instead.

When a bump lands, Railway shows an **update available** notice in your project. Updates are opt-in: apply them when it suits you. Sure migrates the database on start, and your volumes are kept.

## Local testing

`scripts/smoke-test.sh` builds the image and starts it with Postgres and Redis from `docker-compose.yml`. It checks that signup is closed and pages need a login, that the generated admin can log in and finish onboarding, that a profile photo is saved on the volume, that a tag can be created, that the worker is running, and that data survives a restart.

## License

The files in this repository are MIT licensed. Sure is [AGPL-3.0](https://github.com/we-promise/sure/blob/main/LICENSE), made by the [we-promise](https://github.com/we-promise) community. This template runs the official image unmodified.
