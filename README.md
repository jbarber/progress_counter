# ProgressCounter

Thread-safe progress counter for ActiveRecord fan-out/fan-in processes. Perfect for tracking progress across concurrent ActiveJob workers with atomic database operations.

## The Problem

When implementing fan-out/fan-in patterns with ActiveJob, you often need to know when all jobs have completed. A naive approach might be:

```ruby
# DON'T DO THIS - Race condition!
if MyModel.where(batch_id: batch_id, status: 'completed').count == total_jobs
  # This job thinks it's the last one, but another job might also reach this!
  FinalizeJob.perform_later(batch_id)
end
```

This approach has a critical race condition: if multiple jobs complete simultaneously and check the count at the same time, they might all think they're the "last" job and trigger the finalization multiple times.

## The Solution

ProgressCounter provides a safe, atomic way to track progress and identify the last job using database-level atomic operations:

```ruby
counter = ProgressCounter::Model.create!(
  progressable: batch,
  counter_type: 'completed_jobs',
  target: 10,
  current: 0
)

# In each job:
if counter.incr_and_done?
  # Only ONE job will get true, guaranteed!
  FinalizeJob.perform_later(batch.id)
end
```

The `incr_and_done?` method uses `UPDATE ... RETURNING` to atomically increment and return the new value in a single database operation, eliminating race conditions.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'progress_counter'
```

And then execute:

```bash
bundle install
```

Next, generate and run the migration:

```bash
rails generate progress_counter:migration
rails db:migrate
```

## Usage

### Basic Usage

```ruby
# Create a counter for your batch process
counter = ProgressCounter::Model.create!(
  progressable: batch,           # The object you're tracking (polymorphic)
  counter_type: 'tasks',         # Label for this counter (allows multiple counters per object)
  target: 100,                   # Total number of tasks
  current: 0                     # Starting count (defaults to 0)
)

# In each worker job
result = counter.incr_and_done?

if result
  # This is the last job to complete!
  puts "All tasks completed!"
end
```

### Fan-out/Fan-in Example

```ruby
class ProcessBatchJob < ApplicationJob
  def perform(batch_id)
    batch = Batch.find(batch_id)

    # Create a counter for this batch
    counter = ProgressCounter::Model.create!(
      progressable: batch,
      counter_type: 'items_processed',
      target: batch.items.count
    )

    # Fan out: create a job for each item
    batch.items.each do |item|
      ProcessItemJob.perform_later(item.id, counter.id)
    end
  end
end

class ProcessItemJob < ApplicationJob
  def perform(item_id, counter_id)
    item = Item.find(item_id)
    counter = ProgressCounter::Model.find(counter_id)

    # Process the item
    item.process!

    # Fan in: check if this is the last job
    if counter.incr_and_done?
      # Only the last job executes this
      batch = counter.progressable
      batch.mark_as_complete!
      NotificationMailer.batch_complete(batch).deliver_later
    end
  end
end
```

### Multiple Counters Per Object

You can track multiple progress counters for the same object:

```ruby
batch = Batch.find(batch_id)

# Track processing progress
processing_counter = ProgressCounter::Model.create!(
  progressable: batch,
  counter_type: 'processed',
  target: 100
)

# Track validation progress separately
validation_counter = ProgressCounter::Model.create!(
  progressable: batch,
  counter_type: 'validated',
  target: 100
)
```

The combination of `progressable` and `counter_type` must be unique (enforced by database constraint).

### Using the Trackable Concern

For a cleaner integration, include `ProgressCounter::Trackable` in your models and declare your counters with a DSL:

```ruby
class Topic < ApplicationRecord
  include ProgressCounter::Trackable

  progress_counter :intent
  progress_counter :serp
end
```

This generates six methods per counter:

```ruby
# Create a new counter
topic.create_intent_counter(target: 100)

# Find existing counter (raises RecordNotFound if missing)
topic.intent_counter

# Find existing counter (returns nil if missing)
topic.find_intent_counter

# Find or create counter
topic.intent_counter!(target: 100)

# Reset counter to 0 (optionally update target, raises if missing)
topic.reset_intent_counter
topic.reset_intent_counter(target: 200)

# Destroy counter (returns nil if missing)
topic.destroy_intent_counter
```

The fan-out/fan-in example becomes:

```ruby
class ProcessBatchJob < ApplicationJob
  def perform(batch_id)
    batch = Batch.find(batch_id)
    batch.create_items_counter(target: batch.items.count)

    batch.items.each do |item|
      ProcessItemJob.perform_later(item.id, batch.id)
    end
  end
end

class ProcessItemJob < ApplicationJob
  def perform(item_id, batch_id)
    item = Item.find(item_id)
    batch = Batch.find(batch_id)

    item.process!

    if batch.items_counter.incr_and_done?
      batch.mark_as_complete!
    end
  end
end
```

## API

### `#incr`

Atomically increments the counter and returns a hash with the new value and done status.

```ruby
result = counter.incr
# => { current: 1, done: false }

result[:current]  # => 1
result[:done]     # => false

# When target is reached:
result = counter.incr
# => { current: 5, done: true }
```

### `#incr_and_done?`

Atomically increments the counter and returns `true` if the target is reached. This is the primary method for fan-in coordination.

```ruby
if counter.incr_and_done?
  puts "Target reached!"
end
```

### `#done?`

Checks if the counter has reached its target (without incrementing).

```ruby
counter.done?
# => false

counter.update!(current: counter.target)
counter.done?
# => true
```

## How It Works

The magic happens in the `incr` method, which uses a single atomic SQL operation:

```ruby
def incr
  result = self.class.connection.exec_query(
    self.class.sanitize_sql_array([<<-SQL, id])
      UPDATE progress_counters
      SET current = current + 1
      WHERE id = ?
      RETURNING current, target, (current = target) as done;
    SQL
  ).first

  { current: result["current"], done: result["done"] }
end
```

This `UPDATE ... RETURNING` statement:
1. Locks the row
2. Increments the value
3. **Compares the new value to the target in the database**
4. Returns both the new value and the done status
5. Releases the lock

All in a single database round-trip with no possibility of race conditions. The critical insight is that the comparison `(current = target)` happens **atomically inside the database**, ensuring exactly one worker receives `done: true` — the one whose increment lands precisely on the target.

## Database Support

The `UPDATE ... RETURNING` syntax is supported by:
- **PostgreSQL** (all versions)
- **SQLite** 3.35.0+ (March 2021)
- **MariaDB** 10.5+ (October 2020)

**Note**: MySQL does not support `UPDATE ... RETURNING` and is not compatible with this gem. Use MariaDB or PostgreSQL for production deployments.

## Requirements

- Ruby >= 3.1.0
- ActiveRecord >= 7.0
- ActiveSupport >= 7.0

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bundle exec rspec` to run the tests.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jbarber/progress_counter.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
