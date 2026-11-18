# frozen_string_literal: true

module Trysac
  module RailsOnboardingEngine
    # Immutable value object representing a subject's progress through a Flow.
    class Progress
      # Unique progress identifier.
      # @return [String]
      attr_reader :id

      # Subject identifier.
      # @return [String]
      attr_reader :subject_id

      # Name of the flow.
      # @return [String]
      attr_reader :flow_name

      # Flow version of this progress record.
      # @return [Integer]
      attr_reader :version

      # Current active step name, or nil when completed.
      # @return [Symbol, nil]
      attr_reader :current_step

      # Collected step answers keyed by field symbol.
      # @return [Hash{Symbol => Object}]
      attr_reader :data

      # Data partitioned by step name so invisible step answers can be pruned cleanly.
      # @return [Hash{Symbol => Hash{Symbol => Object}}]
      attr_reader :step_data

      # Ordered list of completed visible step names.
      # @return [Array<Symbol>]
      attr_reader :completed_steps

      # Completion percentage (0..100).
      # @return [Integer]
      attr_reader :percent

      # Attributes every Progress must be built with.
      REQUIRED_ATTRIBUTES = %i[id subject_id flow_name version current_step data completed_steps percent].freeze

      # Attributes compared by {#==} and hashed by {#hash} (every attribute except step_data).
      COMPARED_ATTRIBUTES = REQUIRED_ATTRIBUTES

      # Initializes a Progress value object.
      #
      # @param attributes [Hash] progress attributes
      # @option attributes [String] :id progress id
      # @option attributes [String] :subject_id subject id
      # @option attributes [String] :flow_name flow name
      # @option attributes [Integer] :version flow version
      # @option attributes [Symbol, nil] :current_step current step symbol or nil if complete
      # @option attributes [Hash{Symbol => Object}] :data merged collected data
      # @option attributes [Array<Symbol>] :completed_steps completed visible steps
      # @option attributes [Integer] :percent completion percentage
      # @option attributes [Hash{Symbol => Hash{Symbol => Object}}] :step_data answers per step (default `{}`)
      # @raise [ArgumentError] when a required attribute is missing or an unknown attribute is given
      def initialize(**attributes)
        self.class.check_attributes!(attributes)
        @id, @subject_id, @flow_name = attributes.values_at(:id, :subject_id, :flow_name).map { |v| v.to_s.freeze }
        @version, @percent = attributes.values_at(:version, :percent)
        @current_step = attributes[:current_step]&.to_sym
        assign_answers(attributes)
        freeze
      end

      # Raises ArgumentError unless the attributes hold every required key and no unknown key.
      #
      # @param attributes [Hash{Symbol => Object}] attributes passed to {#initialize}
      # @return [void]
      # @raise [ArgumentError] when a required attribute is missing or an unknown attribute is given
      def self.check_attributes!(attributes)
        missing = REQUIRED_ATTRIBUTES - attributes.keys
        raise ArgumentError, "missing keywords: #{missing.map(&:inspect).join(", ")}" unless missing.empty?

        unknown = attributes.keys - REQUIRED_ATTRIBUTES - [:step_data]
        raise ArgumentError, "unknown keywords: #{unknown.map(&:inspect).join(", ")}" unless unknown.empty?
      end

      # Returns a copy of this Progress with the given attributes replaced.
      #
      # @param changes [Hash{Symbol => Object}] attributes to replace (same keys as {#initialize})
      # @return [Progress]
      def with(**changes)
        self.class.new(**attributes, **changes)
      end

      # Returns the attributes this Progress was built from.
      #
      # @return [Hash{Symbol => Object}]
      def attributes
        { id: @id, subject_id: @subject_id, flow_name: @flow_name, version: @version, current_step: @current_step,
          data: @data, step_data: @step_data, completed_steps: @completed_steps, percent: @percent }
      end

      # Returns true when all visible steps in the flow have been completed.
      #
      # @return [Boolean]
      def complete?
        @current_step.nil?
      end

      # Checks value equality across all progress attributes except step_data.
      #
      # @param other [Object] other object
      # @return [Boolean]
      def ==(other)
        other.is_a?(Progress) && compared_values == other.compared_values
      end
      alias eql? ==

      # Computes a hash code consistent with ==.
      #
      # @return [Integer]
      def hash
        compared_values.hash
      end

      # Serializes this Progress to a JSON-compatible Hash.
      #
      # @return [Hash{String => Object}]
      def to_h
        {
          "id" => @id, "subject_id" => @subject_id, "flow_name" => @flow_name, "version" => @version,
          "current_step" => @current_step&.to_s, "data" => @data.transform_keys(&:to_s),
          "step_data" => @step_data.to_h { |k, v| [k.to_s, v.transform_keys(&:to_s)] },
          "completed_steps" => @completed_steps.map(&:to_s), "percent" => @percent
        }
      end

      # Reconstructs a Progress instance from a serialized Hash with String or Symbol keys.
      #
      # @param hash [Hash] serialized attributes
      # @return [Progress]
      def self.from_h(hash)
        read = ->(key, default = nil) { hash[key.to_s] || hash[key] || default }
        new(**identity_from(read), **answers_from(read))
      end

      def self.identity_from(read)
        { id: read.call(:id), subject_id: read.call(:subject_id, ""), flow_name: read.call(:flow_name),
          version: Integer(read.call(:version)), current_step: parse_current_step(read.call(:current_step)),
          percent: Integer(read.call(:percent, 0)) }
      end

      def self.answers_from(read)
        { data: read.call(:data, {}).transform_keys(&:to_sym), step_data: parse_step_data(read.call(:step_data)),
          completed_steps: read.call(:completed_steps, []).map(&:to_sym) }
      end
      private_class_method :identity_from, :answers_from

      # Parses a serialized current step, treating nil and the empty string as "completed".
      #
      # @param raw [String, Symbol, nil] serialized step name
      # @return [Symbol, nil]
      def self.parse_current_step(raw)
        raw.nil? || raw.to_s.empty? ? nil : raw.to_sym
      end

      # Parses serialized per-step answers into Symbol-keyed hashes.
      #
      # @param raw [Hash, nil] serialized step data
      # @return [Hash{Symbol => Hash{Symbol => Object}}]
      def self.parse_step_data(raw)
        (raw || {}).to_h { |step_k, fields_h| [step_k.to_sym, (fields_h || {}).transform_keys(&:to_sym)] }
      end

      protected

      # Values compared by {#==}.
      #
      # @return [Array<Object>]
      def compared_values
        COMPARED_ATTRIBUTES.map { |name| attributes.fetch(name) }
      end

      private

      def assign_answers(attributes)
        @data = attributes[:data].transform_keys(&:to_sym).freeze
        @step_data = freeze_step_data(attributes.fetch(:step_data, {}))
        @completed_steps = attributes[:completed_steps].map(&:to_sym).freeze
      end

      def freeze_step_data(raw)
        raw.to_h do |k, v|
          [k.to_sym, (v || {}).transform_keys(&:to_sym).freeze]
        end.freeze
      end
    end
  end
end
