# typed: strict
# frozen_string_literal: true

require "fileutils"
require_relative "../boot"

module Migrator
  # Generates the baseline migration of `db baseline` (see Migrator.baseline)
  # from the schema snapshot that `db scan` wrote.
  module Baseline
    extend T::Sig

    # The opening line of the block that a dumped schema.rb wraps its definitions in.
    SCHEMA_DEFINITION = /ActiveRecord::Schema\[.*\]\.define\(.*\)\s+do/
    public_constant :SCHEMA_DEFINITION

    class << self
      extend T::Sig

      # Write the baseline migration +name+ for the snapshot in Boot::SCHEMA_FILE,
      # versioned with the current time. The migrations directory is created when
      # it does not exist yet (e.g. a separate AR_MIGRATIONS_DIR).
      #
      # @param name [String] the migration name, e.g. baseline_schema
      # @return [String] the version of the new migration
      sig { params(name: String).returns(String) }
      def write(name)
        version = Time.now.utc.strftime("%Y%m%d%H%M%S")
        filename = path(version, name)
        File.write(filename, migration_source(ActiveSupport::Inflector.camelize(name), schema_body(Boot::SCHEMA_FILE)))
        puts "Wrote baseline migration -> #{filename}"
        version
      end

      # Explain what happened once the baseline +version+ is stamped.
      #
      # @param version [String] the baseline version
      # @return [String] the version
      sig { params(version: String).returns(String) }
      def announce(version)
        puts
        puts "Done. This database is now under migration control at version #{version}."
        puts "Fresh databases will rebuild the full schema from this migration; from"
        puts "here on, add new migrations with later timestamps and run `db migrate`."
        version
      end

      # Extract the contents of the `ActiveRecord::Schema[...].define(...) do ... end`
      # block from a dumped schema.rb, re-indented for a migration body.
      #
      # @param schema_file [String] a schema.rb written by Migrator.scan
      # @return [String] the body of the define block
      sig { params(schema_file: String).returns(String) }
      def schema_body(schema_file)
        # `scan` writes UTF-8; read it as such whatever the locale.
        lines = definition_lines(File.binread(schema_file).force_encoding(Encoding::UTF_8).lines)
        raise "Could not find a schema definition in #{schema_file}. Run `db scan` first." unless lines

        lines.map { |line| indent(line) }.join
      end

      # Render the baseline migration file. `change` is reversible (create_table /
      # add_foreign_key both reverse cleanly), so the baseline can also be rolled
      # back on a throwaway database.
      #
      # @param class_name [String] the migration class
      # @param body [String] the statements of `change`
      # @return [String] Ruby source of the migration
      sig { params(class_name: String, body: String).returns(String) }
      def migration_source(class_name, body)
        <<~RUBY
          # AUTO-GENERATED baseline migration (`db baseline`).
          #
          # It captures the schema as it existed when this database was adopted into
          # migration control. On a FRESH database `db migrate` runs this to build the
          # whole schema from zero. On the ORIGINAL database it was *stamped* as already
          # applied, so it is never executed there.
          class #{class_name} < ActiveRecord::Migration[8.1]
            def change
          #{body.chomp}
            end
          end
        RUBY
      end

      private

      # Where the migration +version+_+name+ goes, creating the directory.
      sig { params(version: String, name: String).returns(String) }
      def path(version, name)
        FileUtils.mkdir_p(Boot::MIGRATIONS_DIR)
        File.join(Boot::MIGRATIONS_DIR, "#{version}_#{name}.rb")
      end

      # Everything between the `define do` line and the file's final `end`, or nil
      # when there is no such block.
      sig { params(lines: T::Array[String]).returns(T.nilable(T::Array[String])) }
      def definition_lines(lines)
        start = lines.index { |line| SCHEMA_DEFINITION.match?(line) }
        finish = lines.rindex { |line| line.rstrip == "end" }
        lines[(start + 1)...finish] if start && finish
      end

      # The dumped body is indented 2 spaces under `define`; add 2 more so it sits
      # neatly inside `def change`. Blank lines stay empty.
      sig { params(line: String).returns(String) }
      def indent(line)
        line.blank? ? "\n" : "  #{line}"
      end
    end
  end
end
