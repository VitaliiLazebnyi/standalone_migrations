# Dockerized ActiveRecord Migrations Playground

A self-contained demonstration of running [Rails-style ActiveRecord
migrations](https://guides.rubyonrails.org/active_record_migrations.html)
against PostgreSQL — **without a full Rails app**. Everything runs in Docker.

It ships three core functions, exposed through a small `db` CLI:

| # | Function | Command | Rails equivalent |
|---|----------|---------|------------------|
| 1 | **Scan** an existing database into a full schema | `db scan` | `rails db:schema:dump` |
| 2 | **Conduct** (apply) migrations | `db migrate` | `rails db:migrate` |
| 3 | **Revert** the last N migrations | `db rollback STEP=n` | `rails db:rollback STEP=n` |

Plus helpers: `db status` (`db:migrate:status`), `db version`, and — for bringing
an **existing/production** database under migration control in one step —
`db baseline` and `db stamp` (see
[Adopting an existing database](docs/ADOPTING-A-DATABASE.md)).

## Architecture

```
┌──────────────────────────┐         ┌────────────────────────────┐
│  app  (ruby:4.0-slim)     │         │  db  (postgres:16)          │
│                           │  TCP    │                             │
│  • activerecord 8.1.3     │ ──5432─▶│  database: app_development  │
│  • pg 1.6.3               │         │  user/pass: app / secret    │
│  • bin/db CLI             │         │                             │
│  • db/migrate/*.rb        │         │  volume: pgdata ───────────┐│
└──────────────────────────┘         └─────────────────────────────┘│
                                       data persists across restarts ┘
```

* **`db` service** — PostgreSQL 16. Its data directory lives on the named
  volume `pgdata`, so **stopping/restarting the container keeps all data**.
  The volume is only removed by an explicit `docker compose down -v`.
* **`app` service** — a Ruby 4.0 container holding the migration code and the
  `db` CLI. Real work is done with one-shot `docker compose run --rm app …`.

### Versions (latest as of June 2026)

* Ruby **4.0.5** (`ruby:4.0-slim`)
* activerecord **8.1.3**
* pg **1.6.3**

Exact gem versions are pinned in the committed **`Gemfile.lock`**, so every
build is reproducible. After changing the `Gemfile`, regenerate it with
`make lock` (writes to the host via the bind mount, keeping the linux build
platforms), then `make build`.

## Quick start

The easiest way is the `make` shortcuts (they start the database for you):

```bash
make setup       # migrate + seed — everything ready in one step
make console     # poke around in psql
make status      # see applied / pending migrations
make rollback STEP=2
make reset       # wipe the data volume and rebuild from scratch
```

Run `make` with no target, or `make help`-style, isn't needed — the full list
is at the top of the [`Makefile`](Makefile).

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

> The first build (run automatically on first use) compiles the `pg` native
> extension and may take a minute.

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

### 3. Revert migrations — `db rollback STEP=n`

Reverts the last `n` applied migrations (the `down` direction). Migrations
written with `change` are reversed automatically; `AddReviewsCountToProducts`
demonstrates an explicit `up`/`down` pair.

```bash
docker compose run --rm app db rollback          # revert 1
docker compose run --rm app db rollback STEP=3   # revert 3
```

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
without running it.

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
|---------|-------|
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

```
docker-compose.yml          # db + app services, pgdata volume
Dockerfile                  # ruby:4.0-slim + pg
Gemfile                     # activerecord, pg
config/database.yml         # connection (env-driven)
Makefile                    # `make` shortcuts (setup / migrate / console / reset / ...)
bin/db                      # the CLI (setup / migrate / rollback / scan / seed / console / baseline / stamp / status / version)
bin/entrypoint.sh           # waits for postgres, then execs the command
lib/boot.rb                 # boots standalone ActiveRecord
lib/migrator.rb             # the core functions
db/migrate/*.rb             # the example migrations
db/seeds.rb                 # example data, loaded by `db seed`
db/schema.rb                # generated by `db scan`
docs/SCHEMA.md              # ERD + index catalogue
docs/DEMO.md                # annotated end-to-end transcript
docs/ADOPTING-A-DATABASE.md # bringing an existing/production DB under migrations
```

## Continuous integration

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on every push and PR:
it builds the image, applies all migrations, **checks `db/schema.rb` is in sync**
(regenerates it with `scan` and fails on any drift), loads the seeds, and proves
every migration is reversible with a full rollback + re-migrate roundtrip.

The schema-drift step is why `scan` matters in CI even when all migrations are
applied: it guarantees the committed `db/schema.rb` always matches what the
migrations actually produce. If it fails, run `make scan` and commit the result.

## Cleanup

```bash
docker compose down        # stop containers, KEEP data
docker compose down -v     # stop containers, DELETE the pgdata volume
```
