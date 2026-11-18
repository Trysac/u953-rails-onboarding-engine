# frozen_string_literal: true

module Trysac
  module RailsOnboardingEngine
    # Deterministic clock for testing time-sensitive operations like token expiration.
    class FrozenClock
      # Current frozen time.
      # @return [Time]
      attr_reader :now

      # Initializes the clock at a given time.
      #
      # @param time [Time] initial timestamp
      def initialize(time = Time.utc(2025, 1, 1, 0, 0, 0))
        @now = time
      end

      # Advances the clock by a given number of seconds.
      #
      # @param seconds [Numeric] seconds to add
      # @return [Time] the updated time
      def advance(seconds)
        @now += seconds
      end

      # Sets the current time explicitly.
      #
      # @param time [Time] new timestamp
      # @return [Time]
      def set(time)
        @now = time
      end
    end
  end
end
