# Orders placed by users, and the line items within each order.
#
# Demonstrates: a composite index tuned for "this user's recent orders"
# ([user_id, created_at]) and a composite unique index on the line items.
class CreateOrdersAndItems < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      t.references :user, null: false, foreign_key: { on_delete: :restrict }
      t.string  :number,        null: false
      t.string  :status,        null: false, default: "pending"
      t.decimal :total_cents,   null: false, default: 0, precision: 12, scale: 0
      t.timestamps
    end
    add_index :orders, :number, unique: true
    # Composite index supporting "ORDER BY created_at WHERE user_id = ?".
    add_index :orders, %i[user_id created_at], name: "idx_orders_on_user_and_created_at"

    create_table :order_items do |t|
      t.references :order,   null: false, foreign_key: { on_delete: :cascade }
      t.references :product, null: false, foreign_key: { on_delete: :restrict }
      t.integer    :quantity,    null: false, default: 1
      t.decimal    :unit_cents,  null: false, default: 0, precision: 12, scale: 0
      t.timestamps
    end
    # A product appears at most once per order (quantity handles multiples).
    add_index :order_items, %i[order_id product_id],
              unique: true, name: "idx_order_items_on_order_and_product"
  end
end
