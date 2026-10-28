# typed: false
# frozen_string_literal: true

# bin/db as a user runs it: a separate process, against this process's test database (DATABASE_NAME is
# inherited) and the example project's migrations.
RSpec.describe "bin/db" do
  it "prints the usage" do
    expect(db("help")).to eq([CLI::USAGE, "", 0])
  end

  # Regression: `db help` printed its own source comments, read in the locale's encoding, and crashed with
  # "invalid byte sequence in US-ASCII" (the usage contains an em dash) when LANG was unset or C.
  it "prints the usage under the C locale" do
    stdout, stderr, status = db("help", environment: { "LANG" => "C", "LC_ALL" => "C" })
    expect([stdout.force_encoding(Encoding::UTF_8), stderr, status]).to eq([CLI::USAGE, "", 0])
  end

  it "fails on an unknown command" do
    expect(db("nope")).to eq(["", "Unknown command: nope\nRun `db help` for usage.\n", 1])
  end

  it "fails on invalid input without a backtrace" do
    expect(db("migrate", "VERSION=")).to eq(["", "VERSION must be a migration version (digits only), got \"\"\n", 1])
  end

  it "migrates the example schema and reports its status", :aggregate_failures do
    stdout, stderr, status = db("migrate")
    expect([stdout.lines.last, stderr, status]).to eq(["Migrated. Current schema version: 20240101000008\n", "", 0])
    expect(db("status").first).to end_with("0 pending migration(s).\n")
  end
end
