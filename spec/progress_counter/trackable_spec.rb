# frozen_string_literal: true

# Define the model class with the Trackable concern outside the block
# to avoid Lint/ConstantDefinitionInBlock
class TrackableTestModel < ActiveRecord::Base
  include ProgressCounter::Trackable

  progress_counter :intent
  progress_counter :serp
end

RSpec.describe ProgressCounter::Trackable do
  before(:all) do
    ActiveRecord::Schema.define do
      create_table :trackable_test_models, force: true do |t|
        t.string :name
        t.timestamps
      end
    end
  end

  after(:all) do
    ActiveRecord::Schema.define do
      drop_table :trackable_test_models, if_exists: true
    end
  end

  let(:model) { TrackableTestModel.create!(name: "test") }

  describe ".progress_counter" do
    it "sets up the has_many association" do
      expect(TrackableTestModel.reflect_on_association(:progress_counters)).to be_present
    end

    it "defines the association only once for multiple counters" do
      associations = TrackableTestModel.reflect_on_all_associations(:has_many)
      progress_counter_associations = associations.select { |a| a.name == :progress_counters }
      expect(progress_counter_associations.count).to eq(1)
    end
  end

  describe "#create_{name}_counter" do
    it "creates a new counter with the given target" do
      counter = model.create_intent_counter(target: 10)

      expect(counter).to be_persisted
      expect(counter.counter_type).to eq("intent")
      expect(counter.target).to eq(10)
      expect(counter.current).to eq(0)
    end

    it "creates different counter types" do
      intent = model.create_intent_counter(target: 10)
      serp = model.create_serp_counter(target: 20)

      expect(intent.counter_type).to eq("intent")
      expect(serp.counter_type).to eq("serp")
    end

    it "raises if counter already exists" do
      model.create_intent_counter(target: 10)

      expect { model.create_intent_counter(target: 10) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "#{name}_counter" do
    it "finds an existing counter" do
      created = model.create_intent_counter(target: 10)

      found = model.intent_counter
      expect(found).to eq(created)
    end

    it "raises if counter does not exist" do
      expect { model.intent_counter }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "#{name}_counter!" do
    it "creates a counter if it does not exist" do
      counter = model.intent_counter!(target: 10)

      expect(counter).to be_persisted
      expect(counter.counter_type).to eq("intent")
      expect(counter.target).to eq(10)
    end

    it "finds an existing counter" do
      created = model.create_intent_counter(target: 10)

      found = model.intent_counter!(target: 10)
      expect(found).to eq(created)
    end

    it "does not update target if counter already exists" do
      model.create_intent_counter(target: 10)

      counter = model.intent_counter!(target: 999)
      expect(counter.target).to eq(10)
    end

    it "handles RecordNotUnique from concurrent creation" do
      model.create_intent_counter(target: 10)

      # Simulate race: find_or_create_by! tries to create and hits unique constraint
      allow(model.progress_counters).to receive(:find_or_create_by!)
        .and_raise(ActiveRecord::RecordNotUnique)

      # Should rescue and fall back to find_by!
      counter = model.intent_counter!(target: 10)
      expect(counter).to be_persisted
      expect(counter.counter_type).to eq("intent")
    end
  end

  describe "#find_{name}_counter" do
    it "returns the counter when it exists" do
      created = model.create_intent_counter(target: 10)

      found = model.find_intent_counter
      expect(found).to eq(created)
    end

    it "returns nil when the counter does not exist" do
      expect(model.find_intent_counter).to be_nil
    end
  end

  describe "#destroy_{name}_counter" do
    it "destroys and returns the counter" do
      model.create_intent_counter(target: 10)

      result = model.destroy_intent_counter
      expect(result).to be_destroyed
      expect(model.find_intent_counter).to be_nil
    end

    it "returns nil when the counter does not exist" do
      expect(model.destroy_intent_counter).to be_nil
    end

    it "allows re-creation after destroy" do
      model.create_intent_counter(target: 10)
      model.destroy_intent_counter

      counter = model.create_intent_counter(target: 20)
      expect(counter).to be_persisted
      expect(counter.target).to eq(20)
    end
  end

  describe "integration with counter methods" do
    it "works with incr_and_done?" do
      model.create_intent_counter(target: 2)

      expect(model.intent_counter.incr_and_done?).to be false
      expect(model.intent_counter.incr_and_done?).to be true
    end
  end
end
