# frozen_string_literal: true

module Trysac
  module RailsOnboardingEngine
    # Bounded in-memory store for onboarding Progress records.
    class MemoryStore
      # Default maximum number of stored entries.
      DEFAULT_MAX_ENTRIES = 10_000

      # Maximum number of entries allowed in the store.
      # @return [Integer]
      attr_reader :max_entries

      # Initializes a MemoryStore.
      #
      # @param max_entries [Integer] capacity limit (default 10_000)
      def initialize(max_entries: DEFAULT_MAX_ENTRIES)
        unless max_entries.is_a?(Integer) && max_entries.positive?
          raise Error.new(:invalid_flow,
                          "max_entries must be positive")
        end

        @max_entries = max_entries
        @records = {}
      end

      # Fetches a stored Progress by id.
      #
      # @param id [String] progress identifier
      # @return [Progress]
      # @raise [Error] with code :not_found when the id is missing
      def fetch(id)
        record = @records[id.to_s]
        raise Error.new(:not_found, "Progress not found: #{id}") if record.nil?

        record
      end

      # Saves or updates a Progress record.
      #
      # @param progress [Progress] progress instance to persist
      # @return [Progress] the saved progress
      # @raise [Error] with code :store_full when capacity is reached for a new id
      def save(progress)
        key = progress.id.to_s
        if !@records.key?(key) && @records.size >= @max_entries
          raise Error.new(:store_full, "MemoryStore limit of #{@max_entries} entries reached")
        end

        @records[key] = progress
      end

      # Returns the current count of stored records.
      #
      # @return [Integer]
      def size
        @records.size
      end
    end
  end
end
