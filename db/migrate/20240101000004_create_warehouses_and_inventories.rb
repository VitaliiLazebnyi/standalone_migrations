# Warehouses and per-warehouse stock levels for products.
#
# Demonstrates: a join table (inventories) connecting two parents (products and
# warehouses) with a COMPOSITE UNIQUE index so a product appears at most once
# per warehouse.
class CreateWarehousesAndInventories < ActiveRecord::Migration[8.1]
  def change
    create_table :warehouses do |t|
      t.string :code,   null: false
      t.string :region, null: false
      t.timestamps
    end
    add_index :warehouses, :code, unique: true

    create_table :inventories do |t|
      t.references :product,   null: false, foreign_key: { on_delete: :cascade }
      t.references :warehouse, null: false, foreign_key: { on_delete: :cascade }
      t.integer    :quantity,  null: false, default: 0
      t.timestamps
    end

    # Composite UNIQUE index: one inventory row per (product, warehouse) pair.
    add_index :inventories, %i[product_id warehouse_id],
              unique: true, name: "idx_inventory_on_product_and_warehouse"
  end
end
