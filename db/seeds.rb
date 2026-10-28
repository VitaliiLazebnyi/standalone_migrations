# typed: true
# frozen_string_literal: true

# Seed data for the example schema. Loaded by `db seed`.
#
# Idempotent: it truncates the domain tables (RESTART IDENTITY CASCADE) and
# re-inserts a small, fully wired-up dataset that exercises every relationship —
# 1:1, self-referential tree, 1:N, M:N, the composite-unique constraints, and
# the reviews counter cache.

# Lightweight ActiveRecord models are defined inline so we don't need a full app.
# They live in the Seeds namespace so that loading this file does not define
# top-level User, Product, ... constants in the caller's process.
module Seeds
  # --- inline models ----------------------------------------------------------
  class User < ActiveRecord::Base; end
  class Profile < ActiveRecord::Base; end
  class Category < ActiveRecord::Base; end
  class Product < ActiveRecord::Base; end
  class Warehouse < ActiveRecord::Base; end
  class Inventory < ActiveRecord::Base; end
  class Order < ActiveRecord::Base; end
  class OrderItem < ActiveRecord::Base; end
  class Tag < ActiveRecord::Base; end
  class ProductTag < ActiveRecord::Base; end
  class Review < ActiveRecord::Base; end

  conn = ActiveRecord::Base.connection

  # --- reset (RESTART IDENTITY so re-seeds are deterministic; CASCADE handles FKs)
  conn.execute(<<~SQL.squish)
    TRUNCATE TABLE
      reviews, order_items, orders, inventories, product_tags,
      products, tags, categories, warehouses, profiles, users
    RESTART IDENTITY CASCADE
  SQL
  puts "Cleared existing rows."

  # --- users + profiles (1:1) --------------------------------------------------
  alice = User.create!(email: "alice@example.com", name: "Alice Doe",   active: true)
  bob   = User.create!(email: "bob@example.com",   name: "Bob Stone",   active: true)
  User.create!(email: "carol@example.com", name: "Carol White", active: false)

  Profile.create!(user_id: alice.id, bio: "Coffee enthusiast", country: "US")
  Profile.create!(user_id: bob.id,   bio: "Marathon runner",   country: "GB")
  # (carol intentionally has no profile)

  # --- categories (self-referential tree) -------------------------------------
  electronics = Category.create!(name: "Electronics", slug: "electronics")
  phones      = Category.create!(name: "Phones", slug: "phones", parent_id: electronics.id)
  audio       = Category.create!(name: "Audio",  slug: "audio",  parent_id: electronics.id)
  home        = Category.create!(name: "Home & Kitchen", slug: "home-kitchen")

  # --- products ----------------------------------------------------------------
  phone   = Product.create!(category_id: phones.id, name: "Nimbus Phone X", sku: "PH-X-001",
                            status: "active", price_cents: 79_900)
  earbuds = Product.create!(category_id: audio.id,  name: "AeroBuds Pro",   sku: "AU-EB-002",
                            status: "active", price_cents: 14_900)
  kettle  = Product.create!(category_id: home.id,   name: "SteepMaster Kettle", sku: "HM-KT-003",
                            status: "draft", price_cents: 5900)

  # --- warehouses + inventories (join, composite-unique product/warehouse) -----
  east = Warehouse.create!(code: "WH-EAST", region: "us-east")
  west = Warehouse.create!(code: "WH-WEST", region: "us-west")

  Inventory.create!(product_id: phone.id,   warehouse_id: east.id, quantity: 120)
  Inventory.create!(product_id: phone.id,   warehouse_id: west.id, quantity: 35)
  Inventory.create!(product_id: earbuds.id, warehouse_id: east.id, quantity: 500)
  Inventory.create!(product_id: kettle.id,  warehouse_id: west.id, quantity: 12)

  # --- tags + product_tags (M:N) ----------------------------------------------
  flagship  = Tag.create!(name: "flagship")
  wireless  = Tag.create!(name: "wireless")
  on_sale   = Tag.create!(name: "on-sale")

  ProductTag.create!(product_id: phone.id,   tag_id: flagship.id)
  ProductTag.create!(product_id: phone.id,   tag_id: on_sale.id)
  ProductTag.create!(product_id: earbuds.id, tag_id: wireless.id)
  ProductTag.create!(product_id: earbuds.id, tag_id: on_sale.id)

  # --- orders + order_items (1:N, composite-unique order/product) --------------
  o1 = Order.create!(user_id: alice.id, number: "ORD-1001", status: "paid",
                     total_cents: phone.price_cents + earbuds.price_cents)
  OrderItem.create!(order_id: o1.id, product_id: phone.id,   quantity: 1, unit_cents: phone.price_cents)
  OrderItem.create!(order_id: o1.id, product_id: earbuds.id, quantity: 1, unit_cents: earbuds.price_cents)

  o2 = Order.create!(user_id: bob.id, number: "ORD-1002", status: "pending",
                     total_cents: earbuds.price_cents * 2)
  OrderItem.create!(order_id: o2.id, product_id: earbuds.id, quantity: 2, unit_cents: earbuds.price_cents)

  # --- reviews (CHECK 1..5, one per user/product) + counter cache --------------
  Review.create!(product_id: phone.id,   user_id: alice.id, rating: 5, body: "Fantastic phone.")
  Review.create!(product_id: phone.id,   user_id: bob.id,   rating: 4, body: "Great, a bit pricey.")
  Review.create!(product_id: earbuds.id, user_id: alice.id, rating: 5, body: "Crystal clear audio.")

  # Keep products.reviews_count consistent with the reviews we just inserted.
  conn.execute(<<~SQL.squish)
    UPDATE products
    SET reviews_count = (SELECT COUNT(*) FROM reviews WHERE reviews.product_id = products.id)
  SQL

  # --- summary -----------------------------------------------------------------
  puts "Seeded:"
  {
    "users" => User, "profiles" => Profile, "categories" => Category,
    "products" => Product, "warehouses" => Warehouse, "inventories" => Inventory,
    "orders" => Order, "order_items" => OrderItem, "tags" => Tag,
    "product_tags" => ProductTag, "reviews" => Review
  }.each { |label, model| puts format("  %<label>-13s %<count>d", label:, count: model.count) }
end
