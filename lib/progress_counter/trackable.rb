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
      # This creates six methods:
      # - `{name}_counter` - finds the existing counter (raises if not found)
      # - `find_{name}_counter` - finds the existing counter (returns nil if not found)
      # - `create_{name}_counter(target:)` - creates a new counter
      # - `{name}_counter!(target:)` - finds or creates the counter
      # - `destroy_{name}_counter` - destroys the counter (returns nil if not found)
      # - `reset_{name}_counter(target: nil)` - resets current to 0 (raises if not found)
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
      #   topic.find_intent_counter           # nil if missing
      #   topic.destroy_intent_counter        # clean up
      #   topic.reset_intent_counter          # re-run
      #
      def progress_counter(name)
        # Set up association once
        unless reflect_on_association(:progress_counters)
          has_many :progress_counters,
                   as: :progressable,
                   class_name: "ProgressCounter::Model",
                   dependent: :destroy
        end

        # Accessor - finds existing counter (raises if not found)
        define_method("#{name}_counter") do
          progress_counters.find_by!(counter_type: name.to_s)
        end

        # Nil-safe accessor - finds existing counter or returns nil
        define_method("find_#{name}_counter") do
          progress_counters.find_by(counter_type: name.to_s)
        end

        # Destroys the counter if it exists, returns nil otherwise
        define_method("destroy_#{name}_counter") do
          counter = progress_counters.find_by(counter_type: name.to_s)
          counter&.destroy
        end

        # Creator - builds new counter with target
        define_method("create_#{name}_counter") do |target:|
          progress_counters.create!(counter_type: name.to_s, target:)
        end

        # Resets current to 0 (and optionally updates target). Raises if not found.
        define_method("reset_#{name}_counter") do |target: nil|
          counter = progress_counters.find_by!(counter_type: name.to_s)
          attrs = { current: 0 }
          attrs[:target] = target if target
          counter.update!(attrs)
          counter
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
