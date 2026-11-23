# Deploy and Host Sure (Self-Hosted Personal Finance, Maybe Fork) on Railway

Sure is an open-source personal finance app, the community fork of Maybe. Track bank accounts, budgets, investments and net worth in one dashboard, import CSVs and statements, and sync banks. It is a self-hosted alternative to Mint, YNAB and Monarch Money, so your financial data stays on a server you control.

## About Hosting Sure

This template runs the official Sure image with Postgres and Redis on Railway's private network, each with its own volume.

Out of the box, a new Sure install lets anyone who opens it sign up. This template closes signup from the first boot and creates your account from `ADMIN_EMAIL` and a generated password, so a stranger can't claim your instance.

After deploying:

1. Open the Sure service's public URL.
2. Log in with `ADMIN_EMAIL` and `ADMIN_PASSWORD` from the service's Variables tab.
3. Fill in your name, country and currency.
4. Add an account by hand, import a CSV, or connect a bank under Settings → Bank sync.

A GitHub Action checks for new stable Sure releases every day and smoke-tests each one before it reaches you. Railway then shows an update notice in your project, and you apply it when it suits you. Your volumes are kept.

## Common Use Cases

- Track net worth across bank accounts, credit cards, investments and property
- Set monthly budgets and see where your money goes by category
- Replace Mint, YNAB or Monarch Money without handing your data to a company
- Share one finance dashboard with your partner or family
- Import years of bank history from CSV files and statements

## Dependencies for Sure Hosting

- Postgres for all financial data
- Redis for the background job queue
- Optional: an OpenAI API key for the AI chat and automatic categories
- Optional: SMTP for email, and a bank sync provider

### Deployment Dependencies

- Sure: https://github.com/we-promise/sure
- Sure self-hosting docs: https://github.com/we-promise/sure/tree/main/docs/hosting
- Template source: https://github.com/railhost/sure-railway

### Implementation Details

The web app and the Sidekiq worker run side by side in one service. The worker reads the files you upload (CSV imports, PDF statements, exports), and Railway can't share a volume between two services. If either process stops, the container exits and Railway restarts it.

Sure's volume is mounted at `/rails/storage` and holds profile photos, imports, statements and exports. The service uses about 700 MB of memory at rest; plan for 1 GB.

Never change `SECRET_KEY_BASE` after the first boot. It encrypts saved bank credentials, and changing it makes them unreadable.

## Why Deploy Sure on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying Sure on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.
