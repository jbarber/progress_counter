# frozen_string_literal: true

module ProgressCounter
  class Model < ActiveRecord::Base
    self.table_name = "progress_counters"

    belongs_to :progressable, polymorphic: true

    validates_presence_of :target
    validates_presence_of :counter_type
    validates :current, numericality: { greater_than_or_equal_to: 0 }

    attribute :current, :integer, default: 0

    # Atomically increments the counter and returns a hash with the new value and done status.
    # This uses a direct SQL UPDATE...RETURNING statement to ensure
    # thread-safety across concurrent workers.
    #
    # The comparison with target happens atomically in the database, ensuring that
    # exactly one worker receives done=true - the one whose increment lands exactly
    # on the target. Workers incrementing past the target receive done=false.
    #
    # @return [Hash] { current: Integer, done: Boolean }
    def incr
      result = self.class.connection.exec_query(
        self.class.sanitize_sql_array([<<-SQL, id])
          UPDATE #{self.class.table_name}
          SET current = current + 1
          WHERE id = ?
          RETURNING current, target, (current = target) as done;
        SQL
      ).first

      counter_value = result["current"]
      write_attribute(:current, counter_value)

      # Normalize the boolean across different databases
      # PostgreSQL returns true/false, SQLite returns 1/0, some may return "t"/"f"
      done = [true, 1, "t"].include?(result["done"])

      { current: counter_value, done: done }
    end

    # Atomically increments the counter and checks if the target is reached
    # This is the main method for fan-in coordination - the last job to complete
    # will be the one where this method returns true
    #
    # @return [Boolean] true if the counter has reached the target after incrementing
    def incr_and_done?
      incr[:done]
    end

    # Checks if the counter has reached its target
    #
    # @return [Boolean] true if current equals target
    def done?
      current == target
    end
  end
end
