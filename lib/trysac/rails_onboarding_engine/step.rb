# frozen_string_literal: true

require_relative "field"

module Trysac
  module RailsOnboardingEngine
    # Represents a single step in an onboarding flow with fields and visibility condition.
    class Step
      # Step identifier.
      # @return [Symbol]
      attr_reader :name

      # Fields defined on this step, keyed by field name.
      # @return [Hash{Symbol => Field}]
      attr_reader :fields

      # Optional visibility predicate.
      # @return [Proc, nil]
      attr_reader :condition

      # DSL builder for configuring fields inside a step block.
      class Builder
        # Initializes the step builder.
        def initialize
          @fields = {}
        end

        # Declares a field on the step.
        #
        # @param name [Symbol, String] field name
        # @param type [Symbol] field type (:string, :email, :integer, :boolean, :enum)
        # @param required [Boolean] whether the field is mandatory
        # @param opts [Hash] additional options (:in, :min, :max)
        # @return [Field]
        def field(name, type: :string, required: false, **opts)
          sym = name.to_sym
          raise Error.new(:invalid_flow, "Duplicate field #{sym}") if @fields.key?(sym)

          @fields[sym] = Field.new(sym, type: type, required: required, allowed_values: opts[:in], min: opts[:min],
                                        max: opts[:max])
        end

        # Returns the frozen fields hash.
        # @return [Hash{Symbol => Field}]
        def build_fields
          @fields.dup.freeze
        end
      end

      # Initializes a Step.
      #
      # @param name [Symbol, String] step identifier
      # @param condition [Proc, nil] visibility condition taking the current data hash
      # @param fields [Hash{Symbol => Field}] step fields
      def initialize(name, condition: nil, fields: {})
        raise Error.new(:invalid_flow, "Step name cannot be empty") if name.nil? || name.to_s.strip.empty?
        if !condition.nil? && !condition.respond_to?(:call)
          raise Error.new(:invalid_flow, "Step condition must be callable")
        end

        @name = name.to_sym
        @condition = condition
        @fields = fields.dup.freeze
        freeze
      end

      # Evaluates whether the step is visible for the given collected data.
      #
      # @param data [Hash{Symbol => Object}] current collected answers
      # @return [Boolean]
      def visible?(data)
        return true if @condition.nil?

        !@condition.call(data).nil? && @condition.call(data) != false
      end

      # Validates a hash of submitted parameters against the step's fields.
      # Unknown keys are dropped.
      #
      # @param params [Hash] submitted parameters
      # @return [Array(Hash{Symbol => Object}, Hash{Symbol => Array<String>})] coerced values and field errors
      def validate(params)
        normalized = normalize_params(params)
        results = @fields.to_h { |fname, field_def| [fname, field_def.validate(normalized[fname])] }
        failed, passed = results.partition { |_fname, (_val, errs)| errs.any? }
        coerced = passed.to_h { |fname, (val, _errs)| [fname, val] }.compact
        [coerced, failed.to_h { |fname, (_val, errs)| [fname, errs] }]
      end

      private

      def normalize_params(params)
        return {} if params.nil?
        raise Error.new(:payload_too_large, "Params must be a Hash") unless params.is_a?(Hash)

        result = {}
        params.each do |k, v|
          sym = k.is_a?(Symbol) ? k : k.to_s.to_sym
          result[sym] = v if @fields.key?(sym)
        end
        result
      end
    end
  end
end
