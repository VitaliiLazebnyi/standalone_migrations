# Adds a denormalised counter-cache column to products.
#
# This migration uses explicit `up`/`down` (instead of `change`) to show how a
# migration defines its own forward and reverse steps — handy for the rollback
# demo, since reverting cleanly drops the column again.
class AddReviewsCountToProducts < ActiveRecord::Migration[8.1]
  def up
    add_column :products, :reviews_count, :integer, null: false, default: 0
    add_index  :products, :reviews_count, name: "idx_products_on_reviews_count"
  end

  def down
    remove_index  :products, name: "idx_products_on_reviews_count"
    remove_column :products, :reviews_count
  end
end
