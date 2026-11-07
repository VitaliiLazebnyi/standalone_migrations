#!/usr/bin/env bash
# The project as a user runs it: the Docker image and docker compose. Applies every migration to a fresh
# database, checks db/schema.rb for drift, loads the seeds, rolls everything back and forth and rejects
# invalid input. Tears the containers and the database volume down afterwards.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# The app container runs as the caller's user, so that `db scan` can write to the checkout.
APP_UID=$(id -u)
APP_GID=$(id -g)
export APP_UID APP_GID

teardown() {
  docker compose down --volumes
}
trap teardown EXIT

docker compose build
docker compose up --detach --wait db

# Apply every migration to a fresh database.
docker compose run --rm app db migrate

# Regenerate db/schema.rb from the live database and fail if it differs from the committed snapshot: the
# checked-in schema must be in sync with the migrations.
docker compose run --rm app db scan
if ! git diff --exit-code db/schema.rb; then
  echo "::error::db/schema.rb is out of date: run 'make scan' and commit the result."
  exit 1
fi

# The seed file must load cleanly against the full schema.
docker compose run --rm app db seed

# Every migration is reversible: roll the whole stack back down and migrate up again.
migrations=$(find db/migrate -name '*.rb' | wc -l)
docker compose run --rm app db rollback "STEP=$((migrations))"
docker compose run --rm app db migrate

# Invalid input is rejected without touching the database.
if docker compose run --rm app db migrate VERSION=; then
  echo "::error::db migrate VERSION= must fail"
  exit 1
fi
status=$(docker compose run --rm app db status)
printf '%s\n' "${status}"
grep --quiet --line-regexp '0 pending migration(s)\.' <<<"${status}"
