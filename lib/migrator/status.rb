# typed: strict
# frozen_string_literal: true

require "active_record"
require "sorbet-runtime"

module Migrator
  # The `db status` table (see Migrator.status): every migration and whether it
  # is applied, like `rails db:migrate:status`.
  module Status
    extend T::Sig

    # One row of the table.
    ROW = "%-8s %-16s %s"
    # The separator lines of the table.
    RULE = T.let("-" * 60, String)
    # The name shown for an applied version without a migration file.
    NO_FILE = "********** NO FILE **********"
    public_constant :ROW, :RULE, :NO_FILE

    class << self
      extend T::Sig

      # Print the table for +migration_context+.
      #
      # @param migration_context [ActiveRecord::MigrationContext]
      # @return [void]
      sig { params(migration_context: ActiveRecord::MigrationContext).void }
      def print(migration_context)
        puts format(ROW, "Status", "Version", "Name"), RULE
        puts rows(migration_context), RULE
        puts "#{migration_context.open.pending_migrations.size} pending migration(s)."
      end

      # One row per migration file or applied version, in version order. An
      # applied version whose migration file is missing is listed as NO FILE.
      #
      # @param migration_context [ActiveRecord::MigrationContext]
      # @return [Array<String>]
      sig { params(migration_context: ActiveRecord::MigrationContext).returns(T::Array[String]) }
      def rows(migration_context)
        applied = migration_context.get_all_versions
        names = names(migration_context)
        versions = names.keys.union(applied).sort
        versions.map { |version| row(version, applied, names) }
      end

      private

      # The class name of each migration file, by version.
      sig { params(migration_context: ActiveRecord::MigrationContext).returns(T::Hash[Integer, String]) }
      def names(migration_context)
        migration_context.migrations.to_h { |migration| [migration.version, migration.name] }
      end

      sig do
        params(version: Integer, applied: T::Array[Integer], names: T::Hash[Integer, String]).returns(String)
      end
      def row(version, applied, names)
        format(ROW, applied.include?(version) ? "  up  " : " down ", version, names.fetch(version, NO_FILE))
      end
    end
  end
end
