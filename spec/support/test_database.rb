# typed: false
# frozen_string_literal: true

# Every test process works in a PostgreSQL database of its own, so that parallel runs (mutant forks one
# process per mutation) never see each other's tables or migration locks. The connection settings come
# from config/database.yml (DATABASE_HOST, DATABASE_PORT, DATABASE_USER, DATABASE_PASSWORD); the user must
# be allowed to create databases.
module TestDatabase
  # Databases are created next to the maintenance database.
  MAINTENANCE = "postgres"
  public_constant :MAINTENANCE

  class << self
    # Create a fresh database for this process, point DATABASE_NAME (read by config/database.yml) at it
    # and connect to it.
    # @return [String] the database name
    def create
      name = "standalone_migrations_test_#{Process.pid}"
      with_maintenance_connection do |connection|
        connection.drop_database(name)
        connection.create_database(name)
      end
      ENV["DATABASE_NAME"] = name
      ActiveRecord::Base.establish_connection(Boot.config)
      name
    end

    # Drop the database of this process.
    # @param name [String]
    # @return [void]
    def drop(name)
      ActiveRecord::Base.connection_handler.clear_all_connections!(:all)
      with_maintenance_connection { |connection| connection.drop_database(name) }
    end

    # Drop every table, so that each example starts from an empty database.
    # @return [void]
    def empty
      connection = ActiveRecord::Base.connection
      connection.tables.each { |table| connection.drop_table(table, force: :cascade) }
    end

    private

    def with_maintenance_connection(&block)
      pool = ActiveRecord::Base.establish_connection(Boot.config.merge("database" => MAINTENANCE))
      pool.with_connection(&block)
    ensure
      ActiveRecord::Base.connection_handler.clear_all_connections!(:all)
    end
  end
end
