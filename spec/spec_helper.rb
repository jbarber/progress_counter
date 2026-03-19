# frozen_string_literal: true

require "active_record"

# Setup in-memory SQLite database for testing BEFORE loading the gem
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

require "progress_counter"

# Load the schema
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

# Define a test model for the polymorphic association
class TestModel < ActiveRecord::Base
  has_many :progress_counters, as: :progressable, class_name: "ProgressCounter::Model"
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Clean up database between tests using transactions
  # Skip this for PostgreSQL concurrency tests which need real commits
  config.around(:each, postgres: false) do |example|
    ActiveRecord::Base.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  end
end
