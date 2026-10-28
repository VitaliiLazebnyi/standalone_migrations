# typed: true
# frozen_string_literal: true

# Product categories, with a self-referential parent_id so categories can form
# a tree (e.g. Electronics -> Phones -> Accessories).
#
# Demonstrates: a self-referencing foreign key.
class CreateCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :categories do |t|
      t.string :name, null: false
      t.string :slug, null: false
      # Self FK: a category's parent is another category. nullify on delete so
      # deleting a parent promotes children to top-level instead of erroring.
      t.references :parent,
                   foreign_key: { to_table: :categories, on_delete: :nullify },
                   index: true
      t.timestamps
    end
    add_index :categories, :slug, unique: true
  end
end
