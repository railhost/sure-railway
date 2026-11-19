#!/usr/bin/env bash
# Starts Sure on $PORT: database migrations, the first admin, then the web
# server and the Sidekiq worker in one container. They share the uploads volume
# at /rails/storage, which Railway can't mount on two services.
set -euo pipefail

STORAGE_DIR=/rails/storage
APP_USER=rails

log() { echo "[railway-entrypoint] $*"; }

# Railway mounts volumes as root. Fix ownership once, then drop privileges.
if [ "$(id -u)" = 0 ]; then
  mkdir -p "$STORAGE_DIR"
  if [ "$(stat -c %U "$STORAGE_DIR")" != "$APP_USER" ]; then
    log "Giving $APP_USER ownership of $STORAGE_DIR"
    chown -R "$APP_USER:$APP_USER" "$STORAGE_DIR"
  fi
  exec setpriv --reuid="$APP_USER" --regid="$APP_USER" --init-groups env HOME=/home/rails "$0" "$@"
fi

cd /rails

# The Postgres variables the app reads (DB_HOST, POSTGRES_USER, ...) come from
# the template. DATABASE_URL alone is not enough for Sure's database.yml.
for v in DB_HOST POSTGRES_USER POSTGRES_PASSWORD REDIS_URL SECRET_KEY_BASE; do
  [ -n "${!v:-}" ] || log "WARNING: $v is not set. Sure will not start correctly without it."
done
if [ -z "${APP_DOMAIN:-}" ] && [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
  export APP_DOMAIN="$RAILWAY_PUBLIC_DOMAIN"
fi

JEMALLOC="/usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2"
[ -f "$JEMALLOC" ] && export LD_PRELOAD="$JEMALLOC"

log "Starting Sure $(tr -d '[:space:]' < .sure-version 2>/dev/null || echo unknown) on port ${PORT:-8080}"
./bin/rails db:prepare
./bin/rails runner /usr/local/share/railway/create-admin.rb

# Run both processes; if either exits, stop the other and exit so Railway restarts us.
./bin/rails server -b "${BINDING:-::}" -p "${PORT:-8080}" &
web=$!
bundle exec sidekiq &
worker=$!
trap 'kill -TERM $web $worker 2>/dev/null' TERM INT

set +e
wait -n $web $worker
status=$?
kill -TERM $web $worker 2>/dev/null
wait
log "A process exited (status $status); stopping."
exit "$status"
