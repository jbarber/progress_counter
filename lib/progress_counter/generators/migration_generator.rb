# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module ProgressCounter
  module Generators
    class MigrationGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      desc "Creates a ProgressCounter migration file"

      def copy_migration
        migration_template "migration.rb.erb", "db/migrate/create_progress_counters.rb"
      end
    end
  end
end
