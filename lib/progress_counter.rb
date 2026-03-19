# frozen_string_literal: true

require "active_support"

require_relative "progress_counter/version"

module ProgressCounter
  class Error < StandardError; end
end

ActiveSupport.on_load(:active_record) do
  require_relative "progress_counter/model"
  require_relative "progress_counter/trackable"
end

require_relative "progress_counter/railtie" if defined?(Rails::Railtie)
