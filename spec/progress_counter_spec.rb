# frozen_string_literal: true

RSpec.describe ProgressCounter do
  it "has a version number" do
    expect(ProgressCounter::VERSION).not_to be nil
  end

  it "defines the Model class" do
    expect(ProgressCounter::Model).to be_a(Class)
  end

  it "Model inherits from ActiveRecord::Base" do
    expect(ProgressCounter::Model.superclass).to eq(ActiveRecord::Base)
  end
end
