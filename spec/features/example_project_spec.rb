# typed: false
# frozen_string_literal: true

# The example project itself: its migrations, its committed schema snapshot and its seed data.
RSpec.describe "the example project" do
  let(:connection) { ActiveRecord::Base.connection }
  let(:tables) do
    %w[categories inventories order_items orders product_tags products profiles reviews tags users warehouses]
  end
  let(:schema) do
    lambda do
      path = File.join(temporary_directory, "schema-#{SecureRandom.hex(4)}.rb")
      stdout_of { Migrator.scan(path) }
      File.read(path)
    end
  end

  let(:without_version) { ->(text) { text.sub(/version: [\d_]+/, "") } }

  before { stdout_of { Migrator.migrate } }

  it "keeps db/schema.rb in sync with the migrations" do
    expect(schema.call).to eq(File.read(ProjectFiles::EXAMPLE_SCHEMA))
  end

  it "has seeds that load into the full schema, repeatedly" do
    2.times { stdout_of { Migrator.seed } }
    counts = tables.map { |table| connection.select_value("SELECT COUNT(*) FROM #{table}") }
    expect(counts).to eq([4, 4, 3, 2, 4, 3, 2, 3, 3, 3, 2])
  end

  it "has seeds that maintain the reviews counter cache" do
    stdout_of { Migrator.seed }
    expect(connection.select_rows("SELECT sku, reviews_count FROM products ORDER BY sku"))
      .to eq([["AU-EB-002", 1], ["HM-KT-003", 0], ["PH-X-001", 2]])
  end

  it "has reversible migrations, all the way down", :aggregate_failures do
    stdout_of { Migrator.rollback(8) }
    expect(connection.tables).to contain_exactly("ar_internal_metadata", "schema_migrations")
    expect(applied_versions).to be_empty
  end

  it "has reversible migrations, which rebuild the same schema on the way up again" do
    before_rollback = schema.call
    stdout_of { Migrator.rollback(8) }
    stdout_of { Migrator.migrate }
    expect(schema.call).to eq(before_rollback)
  end

  # Only the recorded version differs: the baseline's own instead of the last example migration's.
  it "adopts its own database with a baseline that rebuilds it from zero" do
    stdout_of { Migrator.baseline }
    TestDatabase.empty
    ActiveRecord::Migrator.migrations_paths = [Boot::MIGRATIONS_DIR]
    stdout_of { Migrator.migrate }
    expect(without_version[schema.call]).to eq(without_version[File.read(ProjectFiles::EXAMPLE_SCHEMA)])
  end
end
