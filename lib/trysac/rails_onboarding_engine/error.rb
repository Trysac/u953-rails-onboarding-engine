# frozen_string_literal: true

module Trysac
  module RailsOnboardingEngine
    # Base error class for all domain and validation failures in the onboarding engine.
    class Error < ArgumentError
      # Maximum length of any untrusted input snippet included in an error message.
      MAX_MESSAGE_INPUT_LENGTH = 200

      # Machine-readable error code.
      # @return [Symbol]
      attr_reader :code

      # Initializes a new domain error.
      #
      # @param code [Symbol] stable machine-readable error code
      # @param message [String, nil] human-readable message (truncated if necessary)
      def initialize(code, message = nil)
        @code = code.to_sym
        safe_msg = sanitize_message(message || code.to_s)
        super(safe_msg)
      end

      private

      def sanitize_message(msg)
        str = msg.to_s
        return str if str.length <= MAX_MESSAGE_INPUT_LENGTH

        "#{str[0, MAX_MESSAGE_INPUT_LENGTH]}..."
      end
    end
  end
end
