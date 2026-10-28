# typed: true
# frozen_string_literal: true

# Products belong to a category.
#
# Demonstrates: a COMPOSITE index ([category_id, status]) to speed up the very
# common "active products in this category" query, and a partial index.
class CreateProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :products do |t|
      t.references :category, null: false, foreign_key: { on_delete: :restrict }
      t.string  :name,        null: false
      t.string  :sku,         null: false
      t.string  :status,      null: false, default: "draft" # draft|active|archived
      t.decimal :price_cents, null: false, default: 0, precision: 12, scale: 0
      t.timestamps
    end

    add_index :products, :sku, unique: true

    # Composite index: queries filtering by category and status hit this directly.
    add_index :products, %i[category_id status], name: "idx_products_on_category_and_status"

    # Partial index: only active products, keeping the index small/hot.
    add_index :products, :name, where: "status = 'active'", name: "idx_active_products_on_name"
  end
end
