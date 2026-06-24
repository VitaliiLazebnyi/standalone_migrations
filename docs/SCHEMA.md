# Example schema

The eight migrations in `db/migrate/` build the following e-commerce-style
domain. This document is the reference for what each table, relationship, and
index is for.

## Entity-relationship diagram

```
                         ┌──────────────┐
                         │  categories  │── parent_id ─┐ (self-reference: a
                         │              │◀─────────────┘  category tree)
                         └──────┬───────┘
                                │ 1
                                │              ┌───────────────┐
                                │ N            │   warehouses  │
                         ┌──────▼───────┐      └───────┬───────┘
        ┌────────────────│   products   │              │ 1
        │ N              └──┬────────┬───┘              │
        │                 N│       N│                  │ N
┌───────▼──────┐    ┌──────▼───┐  ┌─▼──────────┐  ┌────▼──────────┐
│ product_tags │    │ reviews  │  │ order_items│  │  inventories  │
│ (join M:N)   │    │          │  │            │  │ (per-warehouse│
└───────┬──────┘    └────┬─────┘  └─────┬──────┘  │    stock)     │
        │ N              │ N            │ N        └───────────────┘
      N │            ┌───▼────┐    ┌────▼─────┐
   ┌────▼───┐        │ users  │    │  orders  │
   │  tags  │        │        │◀─1─┤          │ N
   └────────┘        └───┬────┘    └──────────┘
                       1 │
                     ┌───▼─────┐
                     │ profiles│  (1:1 with users)
                     └─────────┘
```

## Tables and relationships

| Table | Key columns | Relationships |
|-------|-------------|---------------|
| `users` | `email` (unique) | has_one `profile`; has_many `orders`, `reviews` |
| `profiles` | `user_id` (unique FK) | belongs_to `user` (**1:1**, `on_delete: cascade`) |
| `categories` | `slug` (unique), `parent_id` | self-referential tree (`on_delete: nullify`) |
| `products` | `sku` (unique), `category_id` | belongs_to `category` (`on_delete: restrict`) |
| `warehouses` | `code` (unique) | has_many `inventories` |
| `inventories` | `product_id`, `warehouse_id` | join of products↔warehouses (stock per warehouse) |
| `orders` | `number` (unique), `user_id` | belongs_to `user` (`on_delete: restrict`) |
| `order_items` | `order_id`, `product_id` | line items of an order (`order` cascade, `product` restrict) |
| `tags` | `name` (unique) | many-to-many with products |
| `product_tags` | `product_id`, `tag_id` | **M:N** join (both cascade) |
| `reviews` | `product_id`, `user_id`, `rating` | belongs_to product & user; rating CHECK 1..5 |

## Foreign-key delete behaviour

| Constraint | `on_delete` | Rationale |
|------------|-------------|-----------|
| `profiles → users` | `cascade` | profile is meaningless without its user |
| `categories → categories` | `nullify` | deleting a parent promotes children to top-level |
| `products → categories` | `restrict` | block deleting a category that still has products |
| `inventories → products / warehouses` | `cascade` | stock rows vanish with their product/warehouse |
| `orders → users` | `restrict` | preserve order history; can't delete a user with orders |
| `order_items → orders` | `cascade` | items belong to the order |
| `order_items → products` | `restrict` | keep historical product reference intact |
| `product_tags → products / tags` | `cascade` | join rows clean up automatically |
| `reviews → products / users` | `cascade` | reviews go with their product/user |

## Index catalogue

| Index | Table | Columns | Type | Purpose |
|-------|-------|---------|------|---------|
| `index_users_on_email` | users | email | unique | one account per email |
| `idx_profiles_on_user_unique` | profiles | user_id | unique | enforce 1:1 |
| `index_categories_on_slug` | categories | slug | unique | URL slug |
| `index_products_on_sku` | products | sku | unique | product code |
| `idx_products_on_category_and_status` | products | category_id, status | **composite** | "active products in a category" |
| `idx_active_products_on_name` | products | name | **partial** (`status='active'`) | small hot index |
| `idx_inventory_on_product_and_warehouse` | inventories | product_id, warehouse_id | **composite unique** | one row per product/warehouse |
| `index_orders_on_number` | orders | number | unique | order number |
| `idx_orders_on_user_and_created_at` | orders | user_id, created_at | **composite** | "this user's recent orders" |
| `idx_order_items_on_order_and_product` | order_items | order_id, product_id | **composite unique** | a product once per order |
| `idx_product_tags_unique` | product_tags | product_id, tag_id | **composite unique** | a tag once per product |
| `idx_product_tags_on_tag` | product_tags | tag_id, product_id | **composite** | reverse lookup "products with tag" |
| `idx_reviews_unique_per_user` | reviews | product_id, user_id | **composite unique** | one review per user/product |
| `idx_reviews_on_product_and_rating` | reviews | product_id, rating | **composite** | highest-rated reviews |
| `idx_products_on_reviews_count` | products | reviews_count | plain | counter-cache lookups |

Plus the single-column FK indexes ActiveRecord adds automatically via
`t.references` (e.g. `index_products_on_category_id`).

## Constraints

* `chk_reviews_rating_range` — `CHECK (rating BETWEEN 1 AND 5)` on `reviews`,
  enforced by the database itself.

## ActiveRecord's internal tables

Besides the 11 domain tables above, ActiveRecord maintains **two** bookkeeping
tables of its own. They are created automatically the first time you run
`db migrate`, and they are deliberately **excluded from `db scan`** (so
`schema.rb` describes your schema, not the framework's plumbing) and from the
seed/row-count helpers.

| Table | Columns | What it is | How the tool uses it |
|-------|---------|------------|----------------------|
| `schema_migrations` | `version` (varchar, **PK**) | The **migration ledger** — one row per applied migration, holding its version timestamp (e.g. `20240101000008`). | `db migrate` inserts a row after each migration and skips versions already present; `db rollback` deletes the row when reverting; `db status` diffs this table against `db/migrate/*.rb` to show up/pending; `db stamp` / `db baseline` write here to mark a version applied **without running it**. |
| `ar_internal_metadata` | `key` (**PK**), `value`, `created_at`, `updated_at` | A small **key/value metadata** store. The main key is `environment` (e.g. `default_env`), which records which environment the database belongs to so Rails can guard against destructive actions against the wrong one. (Some setups also store a `schema_sha1` key.) | Informational guard-rail only — unrelated to domain data. |

Example contents on a fully-migrated database:

```text
schema_migrations.version        ar_internal_metadata
----------------------           key         | value
20240101000001                   ------------+-------------
20240101000002                   environment | default_env
... (one row per migration)
20240101000008
```

> The names are fixed by ActiveRecord. `schema_migrations` is the one the
> migration engine actually depends on; `ar_internal_metadata` is a more general
> framework marker.
