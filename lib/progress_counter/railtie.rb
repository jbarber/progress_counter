# frozen_string_literal: true

require "rails/railtie"

module ProgressCounter
  class Railtie < Rails::Railtie
    railtie_name :progress_counter

    rake_tasks do
      path = File.expand_path(__dir__)
      Dir.glob("#{path}/tasks/**/*.rake").each { |f| load f }
    end

    generators do
      require_relative "generators/migration_generator"
    end
  end
end
