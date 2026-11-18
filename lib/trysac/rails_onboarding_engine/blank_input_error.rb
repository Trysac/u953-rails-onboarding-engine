# frozen_string_literal: true

require_relative "error"

module Trysac
  module RailsOnboardingEngine
    # Raised when a required string input is empty or whitespace-only.
    class BlankInputError < Error
      # Initializes a BlankInputError.
      #
      # @param message [String] error description
      def initialize(message = "Input must not be blank")
        super(:blank_input, message)
      end
    end
  end
end
