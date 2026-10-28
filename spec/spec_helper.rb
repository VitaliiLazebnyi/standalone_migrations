# typed: false
# frozen_string_literal: true

# Must come first: it has to see warnings emitted while bin/, db/, lib/ and spec/ are loaded.
require_relative "support/warning_guard"

require "simplecov"

# Mutation runs execute the suite thousands of times against deliberately broken code; the coverage gate
# is meaningless (and noisy) there.
unless defined?(Mutant)
  SimpleCov.start do
    enable_coverage :branch
    primary_coverage :line
    minimum_coverage line: 100, branch: 100
    # Coverage is measured on lib/ (bin/db only calls CLI.run; spec/ is the suite itself).
    cover "lib/**/*.rb"
  end
end

require "open3"
require_relative "../lib/cli"

# Evaluate every Sorbet signature now: it validates them all up front, and a method that rspec-mocks
# stubs later has no unevaluated signature for sorbet-runtime to drop (with a warning) when it is replaced.
T::Utils.run_all_sig_blocks

Dir[File.join(__dir__, "support", "*.rb")].each { |support_file| require support_file }

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!

  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.include ProjectFiles
  config.include OutputCapture

  # One database per process (see TestDatabase). Mutant runs every mutation in a forked process, which
  # runs the suite hooks again and so gets a database of its own.
  database = nil
  config.before(:suite) { database = TestDatabase.create }
  config.after(:suite) { TestDatabase.drop(database) if database }

  # Every example starts from an empty database, the migrator pointed at the example project's
  # migrations, quiet ActiveRecord logging and the default migration output. The files the code writes
  # (the schema snapshot, baseline migrations) go to a temporary directory, which is also the working
  # directory: neither an example nor a mutation under test may write into the project.
  config.before do
    TestDatabase.empty
    ActiveRecord::Migrator.migrations_paths = [ProjectFiles::EXAMPLE_MIGRATIONS]
    ActiveRecord::Base.logger = nil
    ActiveRecord::Migration.verbose = true
    stub_const("Boot::SCHEMA_FILE", File.join(temporary_directory, "default", "schema.rb"))
    stub_const("Boot::MIGRATIONS_DIR", File.join(temporary_directory, "default", "migrate"))
  end

  config.around do |example|
    Dir.chdir(temporary_directory) { example.run }
  end

  config.after { remove_temporary_directory }

  # Ruby warnings from the project's own files are failures, never noise.
  config.before(:suite) do
    load_time_warnings = WarningGuard.drain
    raise "Ruby warnings while loading:\n#{load_time_warnings.join}" unless load_time_warnings.empty?
  end

  config.after do
    warnings = WarningGuard.drain
    raise "Ruby warnings emitted by this example:\n#{warnings.join}" unless warnings.empty?
  end

  # Pending and skipped examples hide missing behavior: the suite must not contain any.
  config.after(:suite) do
    unfinished = RSpec.world.all_examples.select do |example|
      example.execution_result.status == :pending || example.skipped? || example.pending?
    end
    unless unfinished.empty?
      raise "Pending or skipped examples are not allowed:\n#{unfinished.map(&:full_description).join("\n")}"
    end
  end
end
