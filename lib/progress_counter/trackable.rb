# frozen_string_literal: true

require "active_support/concern"

module ProgressCounter
  # Include this module in your ActiveRecord models to add progress counter support.
  #
  # @example
  #   class Topic < ApplicationRecord
  #     include ProgressCounter::Trackable
  #
  #     progress_counter :intent
  #     progress_counter :serp
  #   end
  #
  #   topic.create_intent_counter(target: 100)
  #   topic.intent_counter.incr_and_done?
  #
  module Trackable
    extend ActiveSupport::Concern

    class_methods do
      # Defines a named progress counter for this model.
      #
      # This creates three methods:
      # - `{name}_counter` - finds the existing counter (raises if not found)
      # - `create_{name}_counter(target:)` - creates a new counter
      # - `{name}_counter!(target:)` - finds or creates the counter
      #
      # @param name [Symbol] the name/type of the counter
      #
      # @example
      #   progress_counter :intent
      #
      #   # Then use:
      #   topic.create_intent_counter(target: 10)
      #   topic.intent_counter.incr_and_done?
      #   topic.intent_counter!(target: 10)  # find or create
      #
      def progress_counter(name)
        # Set up association once
        unless reflect_on_association(:progress_counters)
          has_many :progress_counters,
                   as: :progressable,
                   class_name: "ProgressCounter::Model",
                   dependent: :destroy
        end

        # Accessor - finds existing counter
        define_method("#{name}_counter") do
          progress_counters.find_by!(counter_type: name.to_s)
        end

        # Creator - builds new counter with target
        define_method("create_#{name}_counter") do |target:|
          progress_counters.create!(counter_type: name.to_s, target:)
        end

        # Find or create
        define_method("#{name}_counter!") do |target:|
          progress_counters.find_or_create_by!(counter_type: name.to_s) do |c|
            c.target = target
          end
        rescue ActiveRecord::RecordNotUnique
          progress_counters.find_by!(counter_type: name.to_s)
        end
      end
    end
  end
end
