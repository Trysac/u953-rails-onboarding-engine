# frozen_string_literal: true

require "trysac/rails_onboarding_engine"

# Matchers shared by the onboarding engine specs.
module OnboardingEngineMatchers
  # Matches a raised {Trysac::RailsOnboardingEngine::Error} (or subclass) carrying the given code.
  def raise_engine_error(code)
    raise_error(a_kind_of(Trysac::RailsOnboardingEngine::Error).and(having_attributes(code: code)))
  end
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
  config.include OnboardingEngineMatchers
  config.disable_monkey_patching!
  config.warnings = true
  config.order = :random
  Kernel.srand config.seed
end
