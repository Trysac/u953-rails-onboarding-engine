# frozen_string_literal: true

module Trysac
  module RailsOnboardingEngine
    # System clock returning the current UTC time.
    class Clock
      # Returns the current time.
      #
      # @return [Time]
      def now
        Time.now.utc
      end
    end
  end
end
