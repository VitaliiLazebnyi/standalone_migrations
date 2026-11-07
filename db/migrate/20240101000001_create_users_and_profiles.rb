# typed: true
# frozen_string_literal: true

# Users and their 1:1 profiles.
#
# Demonstrates: a unique index, and a one-to-one relationship enforced with a
# foreign key + unique index on the referencing column.
class CreateUsersAndProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string  :email,    null: false
      t.string  :name,     null: false
      t.boolean :active,   null: false, default: true
      t.timestamps
    end
    # One account per email address.
    add_index :users, :email, unique: true

    create_table :profiles do |t|
      # FK -> users; on_delete: :cascade removes the profile with the user.
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :bio
      t.string :country, limit: 2
      t.timestamps
    end
    # unique => enforces the "one profile per user" (1:1) relationship.
    add_index :profiles, :user_id, unique: true, name: "idx_profiles_on_user_unique"
  end
end
