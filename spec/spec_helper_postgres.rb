# frozen_string_literal: true

require "active_record"

# PostgreSQL configuration
# This requires a PostgreSQL database to be available
# Set environment variables to configure:
#   POSTGRES_HOST (default: localhost)
#   POSTGRES_PORT (default: 5432)
#   POSTGRES_USER (default: postgres)
#   POSTGRES_PASSWORD (default: postgres)
#   POSTGRES_DB (default: progress_counter_test)

def postgres_config
  {
    adapter: "postgresql",
    host: ENV.fetch("POSTGRES_HOST", "localhost"),
    port: ENV.fetch("POSTGRES_PORT", "5432"),
    username: ENV.fetch("POSTGRES_USER", "postgres"),
    password: ENV.fetch("POSTGRES_PASSWORD", "postgres"),
    database: ENV.fetch("POSTGRES_DB", "progress_counter_test"),
    pool: 50 # Support concurrency tests with reasonable resource usage
  }
end

def postgres_available?
  ActiveRecord::Base.establish_connection(postgres_config)
  ActiveRecord::Base.connection.execute("SELECT 1")
  true
rescue StandardError => e
  warn "PostgreSQL not available: #{e.message}"
  warn "Skipping PostgreSQL concurrency tests"
  false
ensure
  ActiveRecord::Base.connection.disconnect! if ActiveRecord::Base.connected?
end

if postgres_available?
  # Establish connection to PostgreSQL
  ActiveRecord::Base.establish_connection(postgres_config)

  require "progress_counter"

  # Load the schema only once
  unless ActiveRecord::Base.connection.table_exists?(:progress_counters)
    ActiveRecord::Schema.define do
      create_table :progress_counters, force: true do |t|
        t.references :progressable, polymorphic: true, null: false
        t.integer :current, default: 0
        t.integer :target, null: false
        t.string :counter_type, null: false
        t.timestamps
      end

      add_index :progress_counters, %i[progressable_type progressable_id counter_type],
                unique: true, name: "idx_progress_counters_unique"

      # Create a test table for the polymorphic association
      create_table :test_models, force: true do |t|
        t.string :name
        t.timestamps
      end
    end
  end

  # Define a test model for the polymorphic association
  class TestModel < ActiveRecord::Base
    has_many :progress_counters, as: :progressable, class_name: "ProgressCounter::Model"
  end

  RSpec.configure do |config|
    config.example_status_persistence_file_path = ".rspec_status"
    config.disable_monkey_patching!

    config.expect_with :rspec do |c|
      c.syntax = :expect
    end

    # Clean up database after each test
    config.after(:each) do
      ProgressCounter::Model.delete_all
      TestModel.delete_all
    end

    config.after(:suite) do
      ActiveRecord::Base.connection.disconnect!
    end
  end
end
