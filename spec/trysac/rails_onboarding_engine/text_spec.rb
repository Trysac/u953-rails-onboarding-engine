# frozen_string_literal: true

require "spec_helper"

RSpec.describe Trysac::RailsOnboardingEngine::Text do
  describe ".normalize" do
    it "trims surrounding whitespace and lower-cases ASCII letters" do
      expect(described_class.normalize("  Hello, World! \n")).to eq("hello, world!")
    end

    it "lower-cases only ASCII letters and leaves non-ASCII characters untouched" do
      expect(described_class.normalize("  ÑOÑO ")).to eq("ÑoÑo")
    end

    it "raises BlankInputError with code :blank_input on empty or whitespace-only input" do
      expect { described_class.normalize("") }.to raise_error(Trysac::RailsOnboardingEngine::BlankInputError) { |e|
        expect(e.code).to eq(:blank_input)
      }
      expect { described_class.normalize("   \t\n ") }.to raise_error(Trysac::RailsOnboardingEngine::BlankInputError)
    end
  end
end
