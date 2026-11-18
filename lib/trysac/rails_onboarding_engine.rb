# frozen_string_literal: true

require_relative "rails_onboarding_engine/version"
require_relative "rails_onboarding_engine/error"
require_relative "rails_onboarding_engine/blank_input_error"
require_relative "rails_onboarding_engine/text"
require_relative "rails_onboarding_engine/clock"
require_relative "rails_onboarding_engine/frozen_clock"
require_relative "rails_onboarding_engine/field"
require_relative "rails_onboarding_engine/step"
require_relative "rails_onboarding_engine/flow"
require_relative "rails_onboarding_engine/progress"
require_relative "rails_onboarding_engine/result"
require_relative "rails_onboarding_engine/memory_store"
require_relative "rails_onboarding_engine/json_file_store"
require_relative "rails_onboarding_engine/token_codec"
require_relative "rails_onboarding_engine/navigator"
require_relative "rails_onboarding_engine/migrator"
require_relative "rails_onboarding_engine/engine"
require_relative "rails_onboarding_engine/cli"

# The namespace of the Trysac factory Ruby libraries.
module Trysac
  # Multi-step onboarding flow engine with declarative steps, conditional branching,
  # versioned migrations, and HMAC-signed resume tokens.
  module RailsOnboardingEngine
  end
end
