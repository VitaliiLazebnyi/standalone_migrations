# typed: false
# frozen_string_literal: true

require "tmpdir"

# Temporary migration directories and schema files, so that examples do not depend on (or change) the
# files of the example project.
module ProjectFiles
  # The migrations of the example project.
  EXAMPLE_MIGRATIONS = File.expand_path("../../db/migrate", __dir__)
  # The committed schema snapshot of the example project.
  EXAMPLE_SCHEMA = File.expand_path("../../db/schema.rb", __dir__)
  public_constant :EXAMPLE_MIGRATIONS, :EXAMPLE_SCHEMA

  # A migration that creates a table with one column, and drops it on the way down.
  # @param table [String]
  # @return [String] the Ruby source
  def self.create_table_source(table)
    <<~RUBY
      class Create#{table.capitalize} < ActiveRecord::Migration[8.1]
        def change
          create_table :#{table} do |t|
            t.string :name
          end
        end
      end
    RUBY
  end

  # A temporary directory, removed after the example.
  # @return [String]
  def temporary_directory
    @temporary_directory ||= Dir.mktmpdir("standalone_migrations")
  end

  # Write a migration that creates +table+ and return its path.
  # @param version [Integer]
  # @param table [String]
  # @param directory [String]
  # @return [String]
  def write_migration(version, table, directory: migrations_directory)
    path = File.join(directory, "#{version}_create_#{table}.rb")
    File.write(path, ProjectFiles.create_table_source(table))
    path
  end

  # The migrations directory of the example (the migrator is pointed at it).
  # @return [String]
  def migrations_directory
    File.join(temporary_directory, "migrate").tap { |directory| FileUtils.mkdir_p(directory) }
  end

  # Point the migrator at #migrations_directory for the duration of the example.
  # @return [void]
  def use_temporary_migrations
    ActiveRecord::Migrator.migrations_paths = [migrations_directory]
  end

  # Boot's file locations as a fresh process computes them from +environment+.
  # @param environment [Hash{String => String}]
  # @return [Array<String>] MIGRATIONS_DIR, SCHEMA_FILE, SEEDS_FILE and ENVIRONMENT
  def boot_constants(environment)
    script = 'require "./lib/boot"; puts Boot::MIGRATIONS_DIR, Boot::SCHEMA_FILE, Boot::SEEDS_FILE, Boot::ENVIRONMENT'
    output, status = Open3.capture2(environment, RbConfig.ruby, "-e", script, chdir: Boot::ROOT)
    raise "boot failed" unless status.success?

    output.lines(chomp: true)
  end

  # Make Boot read +yaml+ as its config/database.yml for the duration of the example.
  # @param yaml [String]
  # @return [void]
  def write_database_yml(yaml)
    root = File.join(temporary_directory, "project")
    FileUtils.mkdir_p(File.join(root, "config"))
    File.write(File.join(root, "config", "database.yml"), yaml)
    stub_const("Boot::ROOT", root)
  end

  # Run bin/db in a separate process (in the project directory, against this process's database).
  # @param arguments [Array<String>]
  # @param environment [Hash{String => String}]
  # @return [Array(String, String, Integer)] stdout, stderr and the exit status
  def db(*, environment: {})
    stdout, stderr, status = Open3.capture3(environment, File.join(Boot::ROOT, "bin", "db"), *, chdir: Boot::ROOT)
    [stdout, stderr, status.exitstatus]
  end

  # The versions recorded in schema_migrations.
  # @return [Array<Integer>]
  def applied_versions
    Migrator.context.get_all_versions
  end

  # Remove the temporary directory.
  # @return [void]
  def remove_temporary_directory
    FileUtils.rm_rf(@temporary_directory) if @temporary_directory
  end
end
