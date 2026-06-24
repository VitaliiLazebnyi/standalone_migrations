# Product reviews written by users.
#
# Demonstrates: two foreign keys on one table, a CHECK constraint, and a
# composite unique index ([product_id, user_id]) so a user reviews a product at
# most once.
class CreateReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :reviews do |t|
      t.references :product, null: false, foreign_key: { on_delete: :cascade }
      t.references :user,    null: false, foreign_key: { on_delete: :cascade }
      t.integer :rating, null: false
      t.text    :body
      t.timestamps
    end

    # Ratings must be 1..5 — enforced in the database, not just the app.
    add_check_constraint :reviews, "rating BETWEEN 1 AND 5", name: "chk_reviews_rating_range"

    # One review per user per product.
    add_index :reviews, %i[product_id user_id], unique: true, name: "idx_reviews_unique_per_user"
    # Supports "highest-rated reviews for a product".
    add_index :reviews, %i[product_id rating], name: "idx_reviews_on_product_and_rating"
  end
end
