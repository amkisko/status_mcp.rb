# frozen_string_literal: true

RSpec.describe StatusMcp do
  it "has a version number" do
    expect(StatusMcp::VERSION).not_to be nil
  end

  it "defines DATA_PATH" do
    expect(defined?(StatusMcp::DATA_PATH)).to eq("constant")
  end
end
