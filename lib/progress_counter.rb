# frozen_string_literal: true

require "active_record"
require "active_support"

require_relative "progress_counter/version"
require_relative "progress_counter/model"
require_relative "progress_counter/trackable"

module ProgressCounter
  class Error < StandardError; end
end

# Load Railtie if Rails is available
require_relative "progress_counter/railtie" if defined?(Rails::Railtie)
