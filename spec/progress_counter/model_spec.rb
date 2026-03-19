# frozen_string_literal: true

RSpec.describe ProgressCounter::Model do
  let(:test_model) { TestModel.create!(name: "Test") }
  let(:counter) do
    described_class.create!(
      progressable: test_model,
      target: 5,
      current: 0,
      counter_type: "test_counter"
    )
  end

  describe "#incr" do
    it "increments the counter atomically" do
      expect { counter.incr }.to change { counter.reload.current }.from(0).to(1)
    end

    it "returns a hash with current and done" do
      result = counter.incr
      expect(result).to be_a(Hash)
      expect(result[:current]).to eq(1)
      expect(result[:done]).to be(false)
    end

    it "returns done true when target is reached" do
      counter.update!(current: 4)
      result = counter.incr
      expect(result[:current]).to eq(5)
      expect(result[:done]).to be(true)
    end

    it "updates the instance's current attribute" do
      counter.incr
      expect(counter.current).to eq(1)
    end

    it "handles multiple increments correctly" do
      3.times { counter.incr }
      expect(counter.reload.current).to eq(3)
    end
  end

  describe "#incr_and_done?" do
    context "when counter reaches target" do
      let(:counter) do
        described_class.create!(
          progressable: test_model,
          target: 1,
          current: 0,
          counter_type: "single_target"
        )
      end

      it "returns true" do
        expect(counter.incr_and_done?).to be(true)
      end
    end

    context "when counter does not reach target" do
      it "returns false" do
        expect(counter.incr_and_done?).to be(false)
      end
    end

    context "when incrementing to exactly the target" do
      before do
        4.times { counter.incr }
      end

      it "returns true on the final increment" do
        expect(counter.incr_and_done?).to be(true)
      end
    end
  end

  describe "#done?" do
    context "when current equals target" do
      before do
        counter.update!(current: 5)
      end

      it "returns true" do
        expect(counter.done?).to be(true)
      end
    end

    context "when current is less than target" do
      it "returns false" do
        expect(counter.done?).to be(false)
      end
    end

    context "after incrementing to target" do
      before do
        5.times { counter.incr }
      end

      it "returns true" do
        expect(counter.done?).to be(true)
      end
    end
  end

  describe "validations" do
    it "requires target" do
      counter = described_class.new(
        progressable: test_model,
        counter_type: "test"
      )
      expect(counter).not_to be_valid
      expect(counter.errors[:target]).to be_present
    end

    it "requires counter_type" do
      counter = described_class.new(
        progressable: test_model,
        target: 5
      )
      expect(counter).not_to be_valid
      expect(counter.errors[:counter_type]).to be_present
    end

    it "requires current to be non-negative" do
      counter = described_class.new(
        progressable: test_model,
        target: 5,
        counter_type: "test",
        current: -1
      )
      expect(counter).not_to be_valid
      expect(counter.errors[:current]).to be_present
    end
  end

  describe "associations" do
    it "belongs to progressable polymorphically" do
      expect(counter.progressable).to eq(test_model)
    end
  end

  describe "uniqueness constraint" do
    it "enforces unique counter_type per progressable" do
      described_class.create!(
        progressable: test_model,
        target: 5,
        counter_type: "unique_test"
      )

      expect do
        described_class.create!(
          progressable: test_model,
          target: 5,
          counter_type: "unique_test"
        )
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows same counter_type for different progressables" do
      test_model2 = TestModel.create!(name: "Test 2")

      described_class.create!(
        progressable: test_model,
        target: 5,
        counter_type: "shared_type"
      )

      expect do
        described_class.create!(
          progressable: test_model2,
          target: 5,
          counter_type: "shared_type"
        )
      end.not_to raise_error
    end
  end

  describe "atomicity" do
    it "uses UPDATE...RETURNING for atomic increments" do
      # Test that incr returns the updated value, demonstrating atomic operation
      expect(counter.incr[:current]).to eq(1)
      expect(counter.incr[:current]).to eq(2)
      expect(counter.incr[:current]).to eq(3)

      # Each increment should be atomic and consistent
      expect(counter.reload.current).to eq(3)
    end

    it "ensures consistent reads after atomic updates" do
      # Multiple increments in sequence should maintain consistency
      5.times { counter.incr }

      # The counter should be at target
      expect(counter.reload.current).to eq(5)
      expect(counter.done?).to be(true)
    end

    it "atomically determines done status in the database" do
      # Set to one before target
      counter.update!(current: 4)

      # The increment that reaches the target should return done: true
      result = counter.incr
      expect(result[:current]).to eq(5)
      expect(result[:done]).to be(true)

      # Subsequent increments past target should return done: false
      # This ensures exactly-once semantics - only one worker gets done: true
      result = counter.incr
      expect(result[:current]).to eq(6)
      expect(result[:done]).to be(false)
    end
  end
end
