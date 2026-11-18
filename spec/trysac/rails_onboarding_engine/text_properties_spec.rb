# frozen_string_literal: true

require "spec_helper"

RSpec.describe Trysac::RailsOnboardingEngine::Text do
  describe ".normalize properties" do
    let(:rng) { Random.new(42) }
    let(:alphabet) { ("a".."z").to_a + ("A".."Z").to_a + ("0".."9").to_a + [" ", "\t"] }

    it "is idempotent and has no surrounding whitespace across generated non-blank inputs" do
      100.times do
        core = Array.new(rng.rand(1..24)) { alphabet.sample(random: rng) }.join
        input = " #{core}x "
        once = described_class.normalize(input)

        expect(described_class.normalize(once)).to eq(once)
        expect(once).to eq(once.strip)
        expect(once).not_to match(/[A-Z]/)
      end
    end
  end

  describe "TokenCodec and Progress invariants" do
    let(:rng) { Random.new(1337) }
    let(:secret) { "a" * 32 }
    let(:clock) { Trysac::RailsOnboardingEngine::FrozenClock.new(Time.utc(2025, 6, 1, 0, 0, 0)) }
    let(:flow) do
      Trysac::RailsOnboardingEngine::Flow.define(:prop_flow) do
        step(:one) { field :val, type: :integer, min: 0, max: 1000, required: true }
        step(:two) { field :flag, type: :boolean, required: true }
      end
    end

    let(:engine) do
      Trysac::RailsOnboardingEngine::Engine.new(flow: flow, store: Trysac::RailsOnboardingEngine::MemoryStore.new,
                                                clock: clock, secret: secret)
    end

    def mutate_one_character(token)
      idx = rng.rand(0...token.length)
      return nil if token[idx] == "."

      token.dup.tap { |mutated| mutated[idx] = token[idx] == "x" ? "y" : "x" }
    end

    it "maintains percent in 0..100" do
      25.times { |i| expect(engine.start("subj-#{i}").percent).to be_between(0, 100) }
    end

    it "rejects any single-character token mutation" do
      25.times do |i|
        mutated = mutate_one_character(engine.resume_token(engine.start("subj-#{i}")))
        next if mutated.nil?

        expect { engine.resume(mutated) }.to raise_error(Trysac::RailsOnboardingEngine::Error)
      end
    end
  end
end
