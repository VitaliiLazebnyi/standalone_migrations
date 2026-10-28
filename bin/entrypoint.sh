#!/bin/sh
# Container entrypoint: wait for PostgreSQL to accept connections, then exec the
# requested command (defaults to `db help`). This makes `docker compose run app
# db migrate` reliable even on a cold start. Gives up after
# DATABASE_WAIT_SECONDS (default 60) instead of waiting forever.
set -eu

host="${DATABASE_HOST:-db}"
port="${DATABASE_PORT:-5432}"
user="${DATABASE_USER:-app}"
wait_seconds="${DATABASE_WAIT_SECONDS:-60}"

if command -v pg_isready >/dev/null 2>&1; then
  echo "Waiting for PostgreSQL at ${host}:${port}..."
  waited=0
  until pg_isready -h "$host" -p "$port" -U "$user" >/dev/null 2>&1; do
    if [ "$waited" -ge "$wait_seconds" ]; then
      echo "PostgreSQL at ${host}:${port} did not accept connections within ${wait_seconds}s." >&2
      exit 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  echo "PostgreSQL is ready."
fi

exec "$@"
