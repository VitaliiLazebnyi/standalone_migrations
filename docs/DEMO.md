# End-to-end demo

A walkthrough of the system, with **real output** captured from a run. SQL
logging is on, so every statement the migration engine issues is visible.

## 0. Start PostgreSQL

```console
$ docker compose up -d db
 Volume migrations_pgdata  Created
 Container migrations_db   Started
```

## 1. Status before migrating

```console
$ docker compose run --rm app db status
Status   Version          Name
------------------------------------------------------------
 down    20240101000001   CreateUsersAndProfiles
 down    20240101000002   CreateCategories
 down    20240101000003   CreateProducts
 down    20240101000004   CreateWarehousesAndInventories
 down    20240101000005   CreateOrdersAndItems
 down    20240101000006   CreateTagsAndProductTags
 down    20240101000007   CreateReviews
 down    20240101000008   AddReviewsCountToProducts
------------------------------------------------------------
8 pending migration(s).
```

## 2. Conduct migrations — `db migrate`

```console
$ docker compose run --rm app db migrate
== 20240101000001 CreateUsersAndProfiles: migrating ===========================
-- create_table(:users)
   (3.1ms)  CREATE TABLE "users" ("id" bigserial primary key, "email" character varying NOT NULL, ...)
   -> 0.0089s
-- add_index(:users, :email, {unique: true})
   (1.5ms)  CREATE UNIQUE INDEX "index_users_on_email" ON "users" ("email")
-- create_table(:profiles)
   (2.3ms)  CREATE TABLE "profiles" (... CONSTRAINT "fk_rails_e424190865"
            FOREIGN KEY ("user_id") REFERENCES "users" ("id") ON DELETE CASCADE)
-- add_index(:profiles, :user_id, {unique: true, name: "idx_profiles_on_user_unique"})
== 20240101000001 CreateUsersAndProfiles: migrated (0.0151s) ==================

  ... (migrations 2 through 7) ...

== 20240101000008 AddReviewsCountToProducts: migrating ========================
-- add_column(:products, :reviews_count, :integer, {null: false, default: 0})
-- add_index(:products, :reviews_count, {name: "idx_products_on_reviews_count"})
== 20240101000008 AddReviewsCountToProducts: migrated (0.0014s) ===============

Migrated. Current schema version: 20240101000008
```

Every version is now recorded in `schema_migrations`:

```console
$ docker compose exec db psql -U app -d app_development -c \
    "SELECT count(*) FROM schema_migrations;"
 count
-------
     8
```

## 3. Scan the database — `db scan`

```console
$ docker compose run --rm app db scan
Scanned 13 tables -> /app/db/schema.rb
```

This writes a complete, runnable `db/schema.rb` reflecting the live database —
all tables, the composite/partial indexes, the foreign keys with their
`on_delete` rules, and the `reviews` CHECK constraint. (Full file:
[`../db/schema.rb`](../db/schema.rb).) Excerpt:

```ruby
ActiveRecord::Schema[8.1].define(version: 2024_01_01_000008) do
  create_table "products", force: :cascade do |t|
    t.bigint "category_id", null: false
    t.string "sku", null: false
    t.string "status", default: "draft", null: false
    t.decimal "price_cents", precision: 12, default: "0", null: false
    t.integer "reviews_count", default: 0, null: false
    t.index ["category_id", "status"], name: "idx_products_on_category_and_status"
    t.index ["name"], name: "idx_active_products_on_name", where: "((status)::text = 'active'::text)"
    t.index ["sku"], name: "index_products_on_sku", unique: true
  end
  # ...
  add_foreign_key "products", "categories", on_delete: :restrict
  add_foreign_key "reviews", "products", on_delete: :cascade
end
```

> `db scan` works on **any** reachable database, not just one built by these
> migrations — handy for capturing the schema of a pre-existing/legacy database.

## 4. Revert migrations — `db rollback STEP=2`

```console
$ docker compose run --rm app db rollback STEP=2
== 20240101000008 AddReviewsCountToProducts: reverting ========================
-- remove_index(:products, {name: "idx_products_on_reviews_count"})
   DROP INDEX "idx_products_on_reviews_count"
-- remove_column(:products, :reviews_count)
   ALTER TABLE "products" DROP COLUMN "reviews_count"
== 20240101000008 AddReviewsCountToProducts: reverted (0.0012s) ===============
== 20240101000007 CreateReviews: reverting ====================================
-- remove_index(:reviews, [:product_id, :rating], ...)
-- remove_check_constraint(:reviews, "rating BETWEEN 1 AND 5", ...)
   DROP TABLE "reviews"
== 20240101000007 CreateReviews: reverted (0.0126s) ===========================

Rolled back 2 migration(s). Current schema version: 20240101000006
```

Status now shows the last two as `down` again:

```console
$ docker compose run --rm app db status
  up     20240101000006   CreateTagsAndProductTags
 down    20240101000007   CreateReviews
 down    20240101000008   AddReviewsCountToProducts
2 pending migration(s).
```

Re-running `db migrate` re-applies them — migrations are repeatable in both
directions.

## 5. Data persists across a restart

```console
$ docker compose exec db psql -U app -d app_development -c \
    "INSERT INTO users (email,name,created_at,updated_at) VALUES ('persist@test.io','Persist Test',now(),now());"
INSERT 0 1

$ docker compose restart db          # stop + start — NOT `down -v`

$ docker compose exec db psql -U app -d app_development -c "SELECT email, name FROM users;"
      email      |     name
-----------------+--------------
 persist@test.io | Persist Test
(1 row)
```

The row — and the `schema_migrations` history — survive because PostgreSQL's
data directory lives on the named `pgdata` volume.
