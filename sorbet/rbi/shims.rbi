# typed: strict

# A migration forwards the schema statements it does not define itself (add_index, add_column, ...) to its
# connection with method_missing, and records them for reversal inside `change`.
class ActiveRecord::Migration
  include ActiveRecord::ConnectionAdapters::SchemaStatements
end
