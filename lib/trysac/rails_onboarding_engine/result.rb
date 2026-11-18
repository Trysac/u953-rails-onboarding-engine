# frozen_string_literal: true

module Trysac
  module RailsOnboardingEngine
    # Returned by Engine#submit to report validation success or per-field errors.
    class Result
      # Updated (or unchanged) Progress instance.
      # @return [Progress]
      attr_reader :progress

      # Map of field name symbols to arrays of error code strings.
      # @return [Hash{Symbol => Array<String>}]
      attr_reader :errors

      # Initializes a Result.
      #
      # @param success [Boolean] whether the step submission succeeded
      # @param progress [Progress] current progress state
      # @param errors [Hash{Symbol => Array<String>}] validation errors
      def initialize(success:, progress:, errors: {})
        @ok = success
        @progress = progress
        @errors = errors.transform_values { |v| v.dup.freeze }.freeze
        freeze
      end

      # Returns true when the step submission passed validation.
      #
      # @return [Boolean]
      def ok?
        @ok
      end
    end
  end
end
