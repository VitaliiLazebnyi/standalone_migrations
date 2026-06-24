# Adopting an existing database into migrations

You have a production database with **schema and data already in it**, and no
migrations. This guide shows how to bring it under migration control — in one
command — and what happens under the hood.

## TL;DR — one command

```bash
docker compose run --rm -e DATABASE_NAME=your_db app db baseline
```

That single command:

1. **scans** the live database into a `schema.rb` snapshot,
2. **generates** a self-contained *baseline* migration from that snapshot, and
3. **stamps** the baseline version as already-applied — *without running it*.

After it, your database is under migration control. Add new migrations with
later timestamps and run `db migrate` as normal.

## Why not just "run migrations"?

`db migrate` records each applied migration as a row in the `schema_migrations`
table, and skips versions already listed there. A pre-existing database has the
**schema but an empty ledger**, so a naive migrate would try to `CREATE TABLE`
things that already exist and fail.

The fix is to *stamp* the current state as a baseline: write the ledger entry
without executing the SQL. `db baseline` automates exactly that.

## The mental model

```
                         db baseline
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
   db scan            generate baseline        db stamp
 (schema.rb)            migration file        (ledger row,
                    (rebuilds schema on        no SQL run)
                     a fresh database)
```

| Where | What the baseline means |
|-------|-------------------------|
| **Existing/production DB** | Stamped as applied. Never executed. Tables & data untouched. |
| **Fresh dev / CI DB** | `db migrate` *runs* the baseline to build the whole schema from zero, then runs any later migrations. |

## Verified walkthrough

Starting from a database created with raw SQL and holding real data
(`authors`, `books`, an author and a book), with **no** migrations:

```console
$ docker compose run --rm -e DATABASE_NAME=legacy_demo app db baseline
Scanned 2 tables -> .../schema.rb
Wrote baseline migration -> .../migrate/20260624185915_baseline_schema.rb
Stamped version 20260624185915 as applied (without running it).

Done. This database is now under migration control at version 20260624185915.
```

The generated migration is a normal, reversible `change` migration:

```ruby
# AUTO-GENERATED baseline migration (`db baseline`).
class BaselineSchema < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pg_catalog.plpgsql"

    create_table "authors", force: :cascade do |t|
      t.text "email", null: false
      t.text "full_name", null: false
      t.unique_constraint ["email"], name: "authors_email_key"
    end

    create_table "books", force: :cascade do |t|
      t.bigint "author_id", null: false
      t.string "isbn", limit: 20, null: false
      t.integer "price_cents", default: 0, null: false
      t.text "title", null: false
      t.index ["isbn"], name: "idx_books_isbn", unique: true
      t.check_constraint "price_cents >= 0", name: "books_price_cents_check"
    end

    add_foreign_key "books", "authors", name: "books_author_id_fkey", on_delete: :cascade
  end
end
```

On the **adopted** database, the baseline shows as applied and migrate is a true
no-op — the existing tables and data are never touched:

```console
$ docker compose run --rm -e DATABASE_NAME=legacy_demo app db status
  up     20260624185915   BaselineSchema
0 pending migration(s).

$ docker compose run --rm -e DATABASE_NAME=legacy_demo app db migrate
Migrated. Current schema version: 20260624185915      # nothing executed

$ # data intact:
 full_name    |        title
--------------+---------------------
 Ada Lovelace | Notes on the Engine
```

On a **fresh, empty** database the same baseline rebuilds everything:

```console
$ docker compose run --rm -e DATABASE_NAME=legacy_fresh app db migrate
== 20260624185915 BaselineSchema: migrating ===========================
   CREATE TABLE "authors" (...)
   CREATE TABLE "books" (...)
== 20260624185915 BaselineSchema: migrated ============================
# -> authors, books, schema_migrations all created from zero.
```

## Doing it by hand (what `baseline` automates)

If you prefer manual control, the same outcome in three steps:

```bash
# 1. snapshot
docker compose run --rm -e DATABASE_NAME=your_db app db scan

# 2. create db/migrate/<version>_baseline_schema.rb yourself
#    (paste the create_table/add_index/add_foreign_key calls from schema.rb)

# 3. stamp that version as applied, without running it
docker compose run --rm -e DATABASE_NAME=your_db app db stamp VERSION=<version>
```

`db stamp VERSION=...` is also useful on its own whenever you need to mark a
specific migration as already done (e.g. you applied a change out-of-band).

## Keeping a separate database in its own migrations directory

`db baseline`/`db migrate`/`db scan` honour two env overrides, so an adopted
database can keep its migrations and snapshot apart from this example project:

```bash
docker compose run --rm \
  -e DATABASE_NAME=your_db \
  -e AR_MIGRATIONS_DIR=/app/your_db/migrate \
  -e AR_SCHEMA_FILE=/app/your_db/schema.rb \
  app db baseline
```

## Production cautions

- **Back up first:** `pg_dump -Fc` before adopting.
- **Never run the baseline migration against the live database** — only stamp it
  (which is what `db baseline` does). Running it would try to recreate existing
  objects.
- **Future production migrations should be additive and safe:** add nullable
  columns then backfill separately; build indexes with
  `add_index ..., algorithm: :concurrently` inside a `disable_ddl_transaction!`
  migration to avoid long table locks.
- **What the snapshot does *not* capture:** views, triggers, stored
  procedures/functions, and custom sequence settings. If your DB relies on
  those, capture them separately with `pg_dump --schema-only` (Rails' `:sql`
  schema format covers this case).
