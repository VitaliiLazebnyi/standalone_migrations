# Tags and the many-to-many join between products and tags.
#
# Demonstrates: a classic many-to-many join table with a composite primary-key
# style unique index, plus a secondary index for reverse lookups.
class CreateTagsAndProductTags < ActiveRecord::Migration[8.1]
  def change
    create_table :tags do |t|
      t.string :name, null: false
      t.timestamps
    end
    add_index :tags, :name, unique: true

    create_table :product_tags do |t|
      t.references :product, null: false, foreign_key: { on_delete: :cascade }
      t.references :tag,     null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
    end
    # Composite unique: a tag is attached to a product at most once.
    add_index :product_tags, %i[product_id tag_id],
              unique: true, name: "idx_product_tags_unique"
    # Reverse-direction index: "all products with this tag".
    add_index :product_tags, %i[tag_id product_id], name: "idx_product_tags_on_tag"
  end
end
