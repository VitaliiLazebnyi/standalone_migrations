# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require "fileutils"
require "open3"
require "shellwords"
require "sorbet-runtime"
require "tmpdir"

# Temporary migration directories and schema files, so that examples do not depend on (or change) the
# files of the example project. Included into every example group (spec/spec_helper.rb).
module ProjectFiles
  extend T::Sig

  # The migrations of the example project.
  EXAMPLE_MIGRATIONS = T.let(File.expand_path("../../db/migrate", __dir__), String)
  # The committed schema snapshot of the example project.
  EXAMPLE_SCHEMA = T.let(File.expand_path("../../db/schema.rb", __dir__), String)
  public_constant :EXAMPLE_MIGRATIONS, :EXAMPLE_SCHEMA

  # A child process (Boot, bin/db) failed.
  class ProcessFailed < StandardError; end

  class << self
    extend T::Sig

    # A migration that creates a table with one column, and drops it on the way down.
    # @param table [String]
    # @return [String] the Ruby source
    sig { params(table: String).returns(String) }
    def create_table_source(table)
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

    # Boot's file locations as a fresh process computes them from +environment+.
    # @param environment [Hash{String => String}]
    # @return [Array<String>] MIGRATIONS_DIR, SCHEMA_FILE, SEEDS_FILE and ENVIRONMENT
    sig { params(environment: T::Hash[String, String]).returns(T::Array[String]) }
    def boot_constants(environment)
      script = 'require "./lib/boot"; puts Boot::MIGRATIONS_DIR, Boot::SCHEMA_FILE, Boot::SEEDS_FILE, Boot::ENVIRONMENT'
      output, status = Open3.capture2(environment, RbConfig.ruby, "-e", script, chdir: Boot::ROOT)
      raise(ProcessFailed, "boot failed") unless status.success?

      output.lines(chomp: true)
    end
  end

  # A temporary directory, removed after the example.
  # @return [String]
  sig { returns(String) }
  def temporary_directory
    @temporary_directory ||= T.let(Dir.mktmpdir("standalone_migrations"), T.nilable(String))
  end

  # Write a migration that creates +table+ and return its path.
  # @param version [Integer]
  # @param table [String]
  # @param directory [String]
  # @return [String]
  sig { params(version: Integer, table: String, directory: String).returns(String) }
  def write_migration(version, table, directory: migrations_directory)
    path = File.join(directory, "#{version}_create_#{table}.rb")
    File.write(path, ProjectFiles.create_table_source(table))
    path
  end

  # The migrations directory of the example (the migrator is pointed at it).
  # @return [String]
  sig { returns(String) }
  def migrations_directory
    File.join(temporary_directory, "migrate").tap { |directory| FileUtils.mkdir_p(directory) }
  end

  # Point the migrator at #migrations_directory for the duration of the example.
  # @return [void]
  sig { void }
  def use_temporary_migrations
    ActiveRecord::Migrator.migrations_paths = [migrations_directory]
  end

  # Write a project directory whose config/database.yml is +yaml+; the examples point Boot::ROOT at it.
  # @param yaml [String]
  # @return [String] the project directory
  sig { params(yaml: String).returns(String) }
  def project_with_database_yml(yaml)
    root = File.join(temporary_directory, "project")
    FileUtils.mkdir_p(File.join(root, "config"))
    File.write(File.join(root, "config", "database.yml"), yaml)
    root
  end

  # Run bin/db in a separate process (in the project directory, against this process's database).
  # @param command [String] the db command
  # @param arguments [Array<String>] its KEY=value arguments
  # @param environment [Hash{String => String}]
  # @return [Array(String, String, Integer)] stdout, stderr and the exit status
  sig do
    params(command: String, arguments: String, environment: T::Hash[String, String])
      .returns([String, String, T.nilable(Integer)])
  end
  def db(command, *arguments, environment: {})
    command_line = Shellwords.join([File.join(Boot::ROOT, "bin", "db"), command, *arguments])
    stdout, stderr, status = Open3.capture3(environment, command_line, chdir: Boot::ROOT)
    [stdout, stderr, status.exitstatus]
  end

  # The versions recorded in schema_migrations.
  # @return [Array<Integer>]
  sig { returns(T::Array[Integer]) }
  def applied_versions
    Migrator.context.get_all_versions
  end

  # Remove the temporary directory.
  # @return [void]
  sig { void }
  def remove_temporary_directory
    directory = @temporary_directory
    FileUtils.rm_rf(directory) if directory
  end
end
