# Dockerized ActiveRecord Migrations Playground

A self-contained demonstration of running [Rails-style ActiveRecord
migrations](https://guides.rubyonrails.org/active_record_migrations.html)
against PostgreSQL — **without a full Rails app**. Everything runs in Docker.

It ships three core functions, exposed through a small `db` CLI:

| # | Function | Command | Rails equivalent |
| --- | --- | --- | --- |
| 1 | **Scan** an existing database into a full schema | `db scan` | `rails db:schema:dump` |
| 2 | **Conduct** (apply) migrations | `db migrate` | `rails db:migrate` |
| 3 | **Revert** the last N migrations | `db rollback STEP=n` | `rails db:rollback STEP=n` |

Plus helpers: `db status` (`db:migrate:status`), `db version`, and — for bringing
an **existing/production** database under migration control in one step —
`db baseline` and `db stamp` (see
[Adopting an existing database](docs/ADOPTING-A-DATABASE.md)).

## Architecture

```text
┌──────────────────────────┐         ┌────────────────────────────┐
│  app  (ruby:4.0.9-alpine) │         │  db  (postgres:18.6)        │
│                           │  TCP    │                             │
│  • activerecord 8.1.4     │ ──5432─▶│  database: app_development  │
│  • pg 1.7.0               │         │  user/pass: app / secret    │
│  • bin/db CLI             │         │                             │
│  • db/migrate/*.rb        │         │  volume: pgdata ───────────┐│
└──────────────────────────┘         └─────────────────────────────┘│
                                       data persists across restarts ┘
```

* **`db` service** — PostgreSQL 18. Its data directory lives on the named
  volume `pgdata`, so **stopping/restarting the container keeps all data**.
  The volume is only removed by an explicit `docker compose down -v`.
* **`app` service** — a Ruby 4.0 container holding the migration code and the
  `db` CLI. Real work is done with one-shot `docker compose run --rm app …`.
  It runs as an unprivileged user with your uid/gid (the Makefile passes them),
  so files it writes through the bind mount belong to you.

### Versions (latest as of October 2026)

* Ruby **4.0.9** (`ruby:4.0.9-alpine3.24`, pinned by digest)
* PostgreSQL **18.6** (`postgres:18.6`, Debian-based, pinned by digest)
* activerecord **8.1.4**
* pg **1.7.0**

Exact gem versions are pinned in the committed **`Gemfile.lock`**, so every
build is reproducible. After changing the `Gemfile`, regenerate it with
`make lock` (writes to the host via the bind mount, keeping the linux build
platforms), then `make build`. CI fails when any dependency falls behind its
newest release (see [CONTRIBUTING.md](CONTRIBUTING.md)); Dependabot proposes
the updates.

### Upgrading from the PostgreSQL 16 setup

Earlier versions of this project ran PostgreSQL 16, whose data files a
PostgreSQL 18 server cannot open. The `pgdata` volume is now mounted at
`/var/lib/postgresql` (PostgreSQL 18 images keep their data in a
version-specific directory below it), so an old volume is left untouched and
the server starts with an empty database. Either rebuild the example data with
`make reset`, or `pg_dump` your data with the old setup first and restore it
into the new server.

## Quick start

The easiest way is the `make` shortcuts (they start the database for you):

```bash
make setup       # migrate + seed — everything ready in one step
make console     # poke around in psql
make status      # see applied / pending migrations
make rollback STEP=2
make reset       # wipe the data volume and rebuild from scratch
```

Run `make` with no target (or `make help`) for the full list.

Each shortcut just wraps the `db` CLI. The underlying commands, if you prefer
them explicit:

```bash
docker compose up -d db                          # start PostgreSQL
docker compose run --rm app db migrate           # apply migrations   (function 2)
docker compose run --rm app db seed              # load example data
docker compose run --rm app db scan              # dump db/schema.rb   (function 1)
docker compose run --rm app db rollback STEP=2   # revert migrations   (function 3)
docker compose run --rm app db status            # applied / pending
```

> Output is **quiet by default** (just migration progress). To see every SQL
> statement, add `VERBOSE=1`: `make migrate VERBOSE=1` (or
> `docker compose run --rm -e VERBOSE=1 app db migrate`).
>
> The first build (run automatically on first use) compiles a few native gem
> extensions and may take a minute.

## The three functions in detail

### 1. Scan — `db scan`

Introspects **every table, column, index, foreign key, and constraint** on the
live connection and serialises them into a runnable `db/schema.rb`, exactly like
`rails db:schema:dump`. It works against any database the connection can see —
even one created outside this tool — which makes it useful for capturing the
schema of a pre-existing/legacy database.

Implemented in `lib/migrator.rb` with `ActiveRecord::SchemaDumper.dump`.

### 2. Conduct migrations — `db migrate`

Runs every pending file in `db/migrate` in version order (the `up` direction),
recording each applied version in the `schema_migrations` table so it is never
run twice. Migrate up to a specific version only:

```bash
docker compose run --rm app db migrate VERSION=20240101000003
```

`VERSION` must be a migration version (digits, optionally grouped with
underscores, as ActiveRecord accepts them); anything else, including an empty
`VERSION=`, is rejected before the database is touched.

### 3. Revert migrations — `db rollback STEP=n`

Reverts the last `n` applied migrations (the `down` direction). Migrations
written with `change` are reversed automatically; `AddReviewsCountToProducts`
demonstrates an explicit `up`/`down` pair.

```bash
docker compose run --rm app db rollback          # revert 1
docker compose run --rm app db rollback STEP=3   # revert 3
```

`STEP` must be a positive integer.

## Adopting an existing / production database

Already have a populated database with no migrations? Bring it under migration
control with a single command:

```bash
docker compose run --rm -e DATABASE_NAME=your_db app db baseline
```

It **scans** the live schema, **generates** a baseline migration from it, and
**stamps** that version as already-applied — without re-running it against your
data. Fresh databases rebuild the full schema from the baseline; the original is
left untouched. `db stamp VERSION=...` marks any single version as applied
without running it. `NAME=...` (default `baseline_schema`) names the baseline
migration; it must be lower case letters, digits and underscores, the file
names ActiveRecord loads. `db status` lists a stamped version that has no
migration file as `NO FILE`.

Full, verified walkthrough (including the safety rules for live databases):
[`docs/ADOPTING-A-DATABASE.md`](docs/ADOPTING-A-DATABASE.md).

## The example database

Eight migrations build an e-commerce-style schema of **11 domain tables**
(13 including the two tables ActiveRecord manages for itself —
`schema_migrations` and `ar_internal_metadata`), richly interrelated. See
[`docs/SCHEMA.md`](docs/SCHEMA.md) for the full ERD, the index/constraint
catalogue, and a section on
[ActiveRecord's internal tables](docs/SCHEMA.md#activerecords-internal-tables).

Highlights:

* **Foreign keys with varied `on_delete` behaviour** — `cascade`, `restrict`,
  and `nullify`.
* **A self-referential FK** — `categories.parent_id → categories.id` (a tree).
* **One-to-one** (`users` ↔ `profiles`), **one-to-many** (`orders` →
  `order_items`), and **many-to-many** (`products` ↔ `tags` via `product_tags`).
* **Composite indexes** — e.g. `products(category_id, status)`,
  `orders(user_id, created_at)`.
* **Composite UNIQUE indexes** — e.g. one inventory row per
  `(product_id, warehouse_id)`, one review per `(product_id, user_id)`.
* **A partial index** — only `status = 'active'` products.
* **A CHECK constraint** — `reviews.rating BETWEEN 1 AND 5`.

## Connecting from your host machine

The `db` service publishes its port to the host as **`localhost:5433`** (mapped
to the container's internal `5432`). Connect with any client:

```bash
PGPASSWORD=secret psql -h 127.0.0.1 -p 5433 -U app -d app_development
# connection URL: postgresql://app:secret@127.0.0.1:5433/app_development
```

| Setting | Value |
| --- | --- |
| Host | `127.0.0.1` (use the IPv4 address, not `localhost`, if you also run a native PostgreSQL) |
| Port | `5433` |
| User / Password | `app` / `secret` |
| Database | `app_development` |

Why 5433? A native (e.g. Homebrew) PostgreSQL often already owns `5432` on the
host and would shadow the container on `localhost`. Publishing on 5433 avoids
the clash. If 5433 is also taken, pick another:

```bash
DB_HOST_PORT=5544 docker compose up -d db   # then connect on 127.0.0.1:5544
```

Note the host port is **only** for your own tools — the `app` container always
reaches the database over the Docker network at `db:5432`, regardless of this.

## Verifying persistence

```bash
docker compose exec db psql -U app -d app_development -c \
  "INSERT INTO users (email,name,created_at,updated_at) VALUES ('a@b.c','A',now(),now());"
docker compose restart db
docker compose exec db psql -U app -d app_development -c "SELECT email FROM users;"
# -> the row is still there. Data lives on the pgdata volume.
```

## Layout

```text
docker-compose.yml          # db + app services, pgdata volume
Dockerfile                  # ruby:4.0.9-alpine + postgresql18-client, non-root
Gemfile                     # activerecord, pg (+ the verification tooling)
config/database.yml         # connection (env-driven)
Makefile                    # `make` shortcuts (setup / migrate / console / reset / test / ...)
bin/db                      # the CLI entry point (calls CLI.run)
bin/entrypoint.sh           # waits for postgres (DATABASE_WAIT_SECONDS), then execs the command
lib/boot.rb                 # boots standalone ActiveRecord
lib/cli.rb, lib/cli/        # argument parsing and the `db` commands
lib/migrator.rb             # the core functions
lib/migrator/               # baseline generation, the status table, input validation
db/migrate/*.rb             # the example migrations
db/seeds.rb                 # example data, loaded by `db seed`
db/schema.rb                # generated by `db scan`
spec/                       # the RSpec suite (runs against a real PostgreSQL)
script/                     # the verification gates (see CONTRIBUTING.md)
sorbet/                     # Sorbet configuration and shims (lib/ and bin/ are `typed: strict`)
docs/SCHEMA.md              # ERD + index catalogue
docs/DEMO.md                # annotated end-to-end transcript
docs/ADOPTING-A-DATABASE.md # bringing an existing/production DB under migrations
```

## Continuous integration

Every push and pull request runs these workflows; each ends with a **warning
gate** job that fails the run when any job log contains a warning or a
deprecation notice:

* **CI** — the RSpec suite against PostgreSQL 18 (100% line and branch
  coverage, Ruby warnings are errors), RuboCop, the inline-suppression scan,
  Sorbet, YARD (100% documented), Reek, Flay, the outdated-dependencies check,
  and the end-to-end Docker run: build the image, apply all migrations,
  **check `db/schema.rb` is in sync** (regenerate it with `scan` and fail on any
  drift), load the seeds, and prove every migration is reversible with a full
  rollback + re-migrate roundtrip.
* **Mutation testing** — Mutant; every mutation must be killed.
* **Security** — bundler-audit, dependency review, gitleaks, and a Trivy scan
  of the built image (no HIGH or CRITICAL finding).
* **Repository lint** — actionlint, zizmor, ShellCheck, hadolint, checkmake,
  markdownlint and typos.
* **CodeQL** and **OpenSSF Scorecard**.

The schema-drift step is why `scan` matters in CI even when all migrations are
applied: it guarantees the committed `db/schema.rb` always matches what the
migrations actually produce. If it fails, run `make scan` and commit the result.

See [CONTRIBUTING.md](CONTRIBUTING.md) for running every gate locally.

## Cleanup

```bash
docker compose down        # stop containers, KEEP data
docker compose down -v     # stop containers, DELETE the pgdata volume
```
