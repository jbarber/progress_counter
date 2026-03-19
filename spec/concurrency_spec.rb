# frozen_string_literal: true

# This spec tests real concurrency using PostgreSQL
# Run with: POSTGRES_DB=progress_counter_test bundle exec rspec spec/concurrency_spec.rb

require_relative "spec_helper_postgres"
require "concurrent" # For CyclicBarrier to synchronize thread starts

if defined?(TestModel) && ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
  RSpec.describe "Concurrency with PostgreSQL", :postgres do
    let!(:test_model) do
      TestModel.create!(name: "Concurrent Test")
    end

    describe "concurrent increments" do
      it "handles concurrent increments without race conditions" do
        num_threads = 30
        counter = ProgressCounter::Model.create!(
          progressable: test_model,
          target: num_threads,
          counter_type: "concurrent_test"
        )

        # Barrier to synchronize thread start - all threads load model then wait
        barrier = Concurrent::CyclicBarrier.new(num_threads)

        # Create threads that will all try to increment
        threads = num_threads.times.map do |i|
          Thread.new do
            # Each thread gets its own connection
            ActiveRecord::Base.connection_pool.with_connection do
              # Find the counter fresh in each thread
              c = ProgressCounter::Model.find(counter.id)

              # Wait for all threads to have loaded their model (timeout after 5 seconds)
              barrier.wait(5)

              result = c.incr
              { thread: i, result: result }
            end
          end
        end

        results = threads.map(&:value)

        # Verify all increments happened
        expect(counter.reload.current).to eq(num_threads)

        # Verify exactly ONE thread got done: true when hitting target
        done_results = results.select { |r| r[:result][:done] }
        expect(done_results.count).to eq(1),
                                      "Expected exactly 1 thread to receive done: true, but got #{done_results.count}"

        # The thread that got done should have seen current == num_threads
        expect(done_results.first[:result][:current]).to eq(num_threads)

        # All counter values should be unique (1 through num_threads)
        counter_values = results.map { |r| r[:result][:current] }.sort
        expect(counter_values).to eq((1..num_threads).to_a)
      end

      it "correctly identifies the last job with incr_and_done?" do
        num_threads = 20
        counter = ProgressCounter::Model.create!(
          progressable: test_model,
          target: num_threads,
          counter_type: "incr_and_done_test"
        )

        # Barrier to synchronize thread start
        barrier = Concurrent::CyclicBarrier.new(num_threads)

        threads = num_threads.times.map do |_i|
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              c = ProgressCounter::Model.find(counter.id)

              # Wait for all threads to have loaded their model (timeout after 5 seconds)
              barrier.wait(5)

              c.incr_and_done?
            end
          end
        end

        thread_results = threads.map(&:value)

        # Exactly one thread should have received true
        expect(thread_results.count(true)).to eq(1)
        expect(thread_results.count(false)).to eq(num_threads - 1)
      end

      it "handles exceeding the target correctly" do
        target = 5
        num_threads = 10
        counter = ProgressCounter::Model.create!(
          progressable: test_model,
          target: target,
          counter_type: "exceed_target_test"
        )

        # Barrier to synchronize thread start
        barrier = Concurrent::CyclicBarrier.new(num_threads)

        # Run more increments than the target
        threads = num_threads.times.map do
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              c = ProgressCounter::Model.find(counter.id)

              # Wait for all threads to have loaded their model (timeout after 5 seconds)
              barrier.wait(5)

              c.incr
            end
          end
        end

        results = threads.map(&:value)

        # Final count should be num_threads
        expect(counter.reload.current).to eq(num_threads)

        # Exactly ONE thread gets done: true - the one that landed on target
        # This is the core guarantee: exactly-once semantics even with extra increments
        done_results = results.select { |r| r[:done] }
        expect(done_results.count).to eq(1),
                                      "Expected exactly 1 thread to receive done: true, but got #{done_results.count}"

        # The thread that got done should have current == target
        expect(done_results.first[:current]).to eq(target)
      end
    end
  end
else
  RSpec.describe "Concurrency with PostgreSQL" do
    it "requires PostgreSQL to be available" do
      skip "PostgreSQL is not configured. Set POSTGRES_* env vars and ensure PostgreSQL is running."
    end
  end
end
