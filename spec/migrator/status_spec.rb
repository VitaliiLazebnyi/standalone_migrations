# typed: false
# frozen_string_literal: true

RSpec.describe Migrator::Status do
  let(:context) { Migrator.context }

  before do
    use_temporary_migrations
    write_migration(10, "alphas")
    write_migration(2, "betas")
    write_migration(30, "gammas")
  end

  describe ".rows" do
    it "lists the migrations in version order, all down on a fresh database" do
      expect(described_class.rows(context)).to eq(
        [" down    2                CreateBetas", " down    10               CreateAlphas",
         " down    30               CreateGammas"]
      )
    end

    it "marks the applied migrations up", :aggregate_failures do
      expect { context.migrate(10) }.to output.to_stdout
      expect(described_class.rows(context).map { |row| row[0, 8] }).to eq(["  up    ", "  up    ", " down   "])
    end

    # Regression: a version recorded in schema_migrations without a migration file (stamped by hand, or a
    # deleted file) was left out of the listing, as if it were not applied.
    it "lists an applied version without a migration file as NO FILE", :aggregate_failures do
      expect { Migrator.stamp("20") }.to output.to_stdout
      expect(described_class.rows(context)).to eq(
        [" down    2                CreateBetas", " down    10               CreateAlphas",
         "  up     20               ********** NO FILE **********", " down    30               CreateGammas"]
      )
    end
  end

  describe ".print" do
    it "prints the table and the number of pending migrations", :aggregate_failures do
      expect { context.migrate(2) }.to output.to_stdout
      expect { described_class.print(context) }.to output(<<~TEXT).to_stdout
        Status   Version          Name
        ------------------------------------------------------------
          up     2                CreateBetas
         down    10               CreateAlphas
         down    30               CreateGammas
        ------------------------------------------------------------
        2 pending migration(s).
      TEXT
    end
  end
end
