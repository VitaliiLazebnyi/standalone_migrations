#!/usr/bin/env bash
# Container entrypoint: wait for PostgreSQL to accept connections, then exec the
# requested command (defaults to `db help`). This makes `docker compose run app
# db migrate` reliable even on a cold start.
set -e

host="${DATABASE_HOST:-db}"
port="${DATABASE_PORT:-5432}"
user="${DATABASE_USER:-app}"

if command -v pg_isready >/dev/null 2>&1; then
  echo "Waiting for PostgreSQL at ${host}:${port}..."
  until pg_isready -h "$host" -p "$port" -U "$user" >/dev/null 2>&1; do
    sleep 1
  done
  echo "PostgreSQL is ready."
fi

exec "$@"
