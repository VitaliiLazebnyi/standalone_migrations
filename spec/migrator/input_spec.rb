# typed: false
# frozen_string_literal: true

RSpec.describe Migrator::Input do
  describe ".migration_version" do
    it "accepts digits" do
      expect(described_class.migration_version("20240101000003")).to eq("20240101000003")
    end

    it "accepts an Integer" do
      expect(described_class.migration_version(20_240_101_000_003)).to eq("20240101000003")
    end

    it "drops underscores that group digits" do
      expect(described_class.migration_version("2024_01_01_000003")).to eq("20240101000003")
    end

    it "strips surrounding whitespace" do
      expect(described_class.migration_version(" 7\n")).to eq("7")
    end

    ["", "abc", "12a", "a12", "1__2", "_1", "1_", "-1", "1.5", "1\n2"].each do |invalid|
      it "rejects #{invalid.inspect}" do
        expect { described_class.migration_version(invalid) }.to raise_error(
          Migrator::InvalidInput, "VERSION must be a migration version (digits only), got #{invalid.strip.inspect}"
        )
      end
    end

    it "is an ArgumentError" do
      expect { described_class.migration_version("x") }.to raise_error(ArgumentError)
    end
  end

  describe ".migration_name" do
    %w[baseline_schema b a1 legacy_v2_ x__y].each do |valid|
      it "accepts #{valid}" do
        expect(described_class.migration_name(valid)).to eq(valid)
      end
    end

    ["", "Baseline", "baseLine", "1baseline", "_baseline", "baseline-schema", "baseline schema", "a\nb",
     "a.b", "../x"].each do |invalid|
      it "rejects #{invalid.inspect}" do
        expect { described_class.migration_name(invalid) }.to raise_error(
          Migrator::InvalidInput, "NAME must be lower case letters, digits and underscores, got #{invalid.inspect}"
        )
      end
    end
  end
end
