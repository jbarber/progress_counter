# frozen_string_literal: true

require "rails/railtie"

module ProgressCounter
  class Railtie < Rails::Railtie
    railtie_name :progress_counter

    generators do
      require_relative "generators/migration_generator"
    end
  end
end
