#!/usr/bin/env bash
# Builds the image, starts Sure with Postgres and Redis (docker-compose.yml) and
# checks what a template user depends on: signup is closed and pages need a login,
# the generated admin can log in, onboarding saves a profile photo to the volume,
# a tag can be created, Sidekiq is running, and data survives a restart.
# Used locally and by CI. Needs docker, curl and openssl.
set -euo pipefail

cd "$(dirname "$0")/.."
PORT="${SMOKE_PORT:-39300}"
BASE="http://127.0.0.1:$PORT"
EMAIL=admin@example.com
export SMOKE_PORT="$PORT" SMOKE_ADMIN_EMAIL="$EMAIL"
export SMOKE_ADMIN_PASSWORD="smoke-$(openssl rand -hex 12)"
export SMOKE_SECRET_KEY_BASE="$(openssl rand -hex 64)"
WORK="$(mktemp -d)"
# Git Bash on Windows: native curl needs C:/ paths, docker needs unconverted /rails paths.
if command -v cygpath >/dev/null; then WORK="$(cygpath -m "$WORK")" && export MSYS_NO_PATHCONV=1; fi
JAR="$WORK/cookies"

compose() { docker compose -p sure-smoke -f docker-compose.yml "$@"; }

cleanup() {
  compose down -v --remove-orphans >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  compose logs --tail 80 sure >&2 || true
  exit 1
}

start() {
  compose up -d >/dev/null 2>&1 || { compose logs --tail 60 >&2; fail "containers did not start"; }
  for _ in $(seq 1 180); do
    [ "$(status /up)" = 200 ] && return 0
    sleep 1
  done
  fail "server did not answer /up"
}

# Usage: status [curl options] <path>. Prints the HTTP status code.
status() {
  local path="${!#}" opts=("${@:1:$#-1}")
  curl -s -o "$WORK/discard" -w '%{http_code}' ${opts[@]+"${opts[@]}"} "$BASE$path" 2>/dev/null || true
}
# Usage: location [curl options] <path>. Prints the redirect target, without the host.
location() {
  local path="${!#}" opts=("${@:1:$#-1}")
  curl -s -o "$WORK/discard" -w '%{redirect_url}' ${opts[@]+"${opts[@]}"} "$BASE$path" | sed "s#^$BASE##"
}
# Logged-in requests share one cookie jar, like a browser.
get() { curl -fsS -b "$JAR" -c "$JAR" "$BASE$1" >"$WORK/page"; }
# Rails accepts the page's csrf-token meta tag for any form on that session.
csrf() { get "$1" && sed -n 's/.*<meta name="csrf-token" content="\([^"]*\)".*/\1/p' "$WORK/page" | head -n1; }
post() {
  local page="$1" action="$2" token
  shift 2
  token="$(csrf "$page")"
  [ -n "$token" ] || fail "no CSRF token on $page"
  curl -sS -o "$WORK/discard" -w '%{http_code} %{redirect_url}' -b "$JAR" -c "$JAR" \
    -F "authenticity_token=$token" "$@" "$BASE$action"
}
psql() { compose exec -T postgres psql -U postgres -d railway -tAc "$1"; }
redis() { compose exec -T redis redis-cli -a smoke-redis-password --no-auth-warning "$@"; }

login() {
  rm -f "$JAR"
  post /sessions/new /sessions -F "email=$EMAIL" -F "password=$1"
}

# 1x1 PNG for the profile photo.
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\rIDATx\x9cc\xf8\x0f\x00\x00\x01\x01\x00\x05\x18\xd8N\x00\x00\x00\x00IEND\xaeB`\x82' >"$WORK/pixel.png"

if [ -z "${SKIP_BUILD:-}" ]; then
  compose build sure
fi
compose down -v --remove-orphans >/dev/null 2>&1 || true

echo "== first boot"
start
echo "Sure $(compose exec -T sure cat /rails/.sure-version)"
for pid in $(compose exec -T sure pgrep -f 'puma|sidekiq'); do
  [ "$(compose exec -T sure stat -c %U "/proc/$pid")" = rails ] || fail "process $pid is not running as the rails user"
done

echo "== signup is closed and pages need a login"
for path in / /accounts /transactions /tags /settings/profile; do
  [ "$(location "$path")" = /sessions/new ] || fail "$path is reachable without a login"
done
[ "$(location /registration/new)" = /sessions/new ] || fail "the signup page is open"
token="$(csrf /sessions/new)"
curl -sS -o "$WORK/discard" -b "$JAR" -c "$JAR" -F "authenticity_token=$token" -F "user[email]=stranger@example.com" \
  -F "user[password]=Stranger-Pass-123!" -F "user[password_confirmation]=Stranger-Pass-123!" "$BASE/registration"
[ "$(psql "select count(*) from users")" = 1 ] || fail "a stranger could sign up"
[ "$(psql "select role from users where email = '$EMAIL'")" = super_admin ] || fail "the admin is not a super_admin"

echo "== login"
result="$(login wrong-password-123)"
[ "$(location -b "$JAR" /)" = /sessions/new ] || fail "a wrong password got a session ($result)"
result="$(login "$SMOKE_ADMIN_PASSWORD")"
[ "$result" = "302 $BASE/" ] || fail "login with the generated password failed ($result)"
[ "$(location -b "$JAR" /)" = /onboarding ] || fail "a new admin was not sent to onboarding"

echo "== onboarding saves the profile and a photo on the volume"
get /onboarding
user_id="$(grep -o 'action="/users/[0-9a-f-]*"' "$WORK/page" | head -n1 | sed 's#.*/users/##; s#"##')"
[ -n "$user_id" ] || fail "no profile form on /onboarding"
result="$(post /onboarding "/users/$user_id" -F _method=patch -F user[redirect_to]=home \
  -F "user[onboarded_at]=$(date -u +%Y-%m-%dT%H:%M:%SZ)" -F user[first_name]=Smoke -F user[last_name]=Test \
  -F "user[profile_image]=@$WORK/pixel.png;type=image/png" \
  -F user[family_attributes][moniker]=Family -F "user[family_attributes][name]=Smoke Family" \
  -F user[family_attributes][country]=US -F user[family_attributes][currency]=USD)"
[ "$result" = "302 $BASE/" ] || fail "onboarding did not save ($result)"
[ "$(status -b "$JAR" /)" = 200 ] || fail "the dashboard did not load after onboarding"
[ "$(compose exec -T sure find /rails/storage -type f | wc -l | tr -d ' ')" -ge 1 ] \
  || fail "the profile photo was not saved in /rails/storage"
get /settings/profile
avatar="$(grep -o '/rails/active_storage/[^"]*' "$WORK/page" | head -n1)"
[ -n "$avatar" ] || fail "the profile page shows no photo"
curl -fsSL -b "$JAR" -o "$WORK/avatar" "$BASE$avatar" || fail "the profile photo does not load"

echo "== create a tag"
result="$(post /tags /tags -F "tag[name]=smoke-tag" -F "tag[color]=#e99537")"
[ "$result" = "302 $BASE/tags" ] || fail "creating a tag failed ($result)"
get /tags
grep -qF smoke-tag "$WORK/page" || fail "the new tag is not listed"

echo "== Sidekiq is running"
for _ in $(seq 1 30); do
  [ "$(redis scard processes)" -ge 1 ] && break
  sleep 1
done
[ "$(redis scard processes)" -ge 1 ] || fail "no Sidekiq process is registered in Redis"

echo "== restart keeps the data"
compose down >/dev/null 2>&1
start
[ "$(status -b "$JAR" /)" = 200 ] || fail "the session did not survive a restart"
result="$(login "$SMOKE_ADMIN_PASSWORD")"
[ "$result" = "302 $BASE/" ] || fail "login failed after restart ($result)"
get /tags
grep -qF smoke-tag "$WORK/page" || fail "the tag is gone after restart"
curl -fsSL -b "$JAR" -o "$WORK/avatar2" "$BASE$avatar" || fail "the profile photo is gone after restart"
[ "$(psql "select count(*) from users")" = 1 ] || fail "the restart created another user"

echo "PASS"
