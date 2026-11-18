# frozen_string_literal: true

module Trysac
  module RailsOnboardingEngine
    # Represents a single typed and validated field within an onboarding step.
    class Field
      # Allowed field types.
      VALID_TYPES = %i[string email integer boolean enum].freeze

      # Optional constraint keywords accepted by {#initialize}.
      CONSTRAINTS = %i[allowed_values min max].freeze

      # Validator method used for each field type.
      VALIDATORS = {
        string: :validate_string, email: :validate_email, integer: :validate_integer,
        boolean: :validate_boolean, enum: :validate_enum
      }.freeze

      # Maximum length for a :string field.
      MAX_STRING_LENGTH = 200

      # Maximum length for an :email field.
      MAX_EMAIL_LENGTH = 254

      # Field name.
      # @return [Symbol]
      attr_reader :name

      # Field type.
      # @return [Symbol]
      attr_reader :type

      # Whether the field is required.
      # @return [Boolean]
      attr_reader :required

      # Allowed values for :enum fields.
      # @return [Array<String>, nil]
      attr_reader :allowed_values

      # Minimum value for :integer fields.
      # @return [Integer, nil]
      attr_reader :min

      # Maximum value for :integer fields.
      # @return [Integer, nil]
      attr_reader :max

      # Initializes a new Field definition.
      #
      # @param name [Symbol, String] field identifier
      # @param type [Symbol] one of VALID_TYPES
      # @param required [Boolean] whether a value must be present
      # @param constraints [Hash] optional type constraints
      # @option constraints [Array<String>, nil] :allowed_values list of valid options for :enum
      # @option constraints [Integer, nil] :min optional minimum for :integer
      # @option constraints [Integer, nil] :max optional maximum for :integer
      # @raise [Error] with code :invalid_flow if definition is invalid
      # @raise [ArgumentError] when an unknown constraint is given
      def initialize(name, type: :string, required: false, **constraints)
        self.class.check_definition!(name, type, constraints)
        @name = name.to_sym
        @type = type
        @required = !required.nil? && required != false
        @allowed_values = constraints[:allowed_values]&.map(&:to_s)&.freeze
        @min = constraints[:min]
        @max = constraints[:max]
        freeze
      end

      # Raises unless the name, type and constraints describe a valid field.
      #
      # @param name [Symbol, String, nil] field identifier
      # @param type [Symbol] field type
      # @param constraints [Hash{Symbol => Object}] constraints passed to {#initialize}
      # @return [void]
      # @raise [Error] with code :invalid_flow if the definition is invalid
      # @raise [ArgumentError] when an unknown constraint is given
      def self.check_definition!(name, type, constraints)
        check_constraint_keys!(constraints)
        raise Error.new(:invalid_flow, "Field name cannot be empty") if name.nil? || name.to_s.strip.empty?
        raise Error.new(:invalid_flow, "Unknown field type: #{type}") unless VALID_TYPES.include?(type)

        check_enum_values!(name, type, constraints[:allowed_values])
      end

      def self.check_constraint_keys!(constraints)
        unknown = constraints.keys - CONSTRAINTS
        raise ArgumentError, "unknown keywords: #{unknown.map(&:inspect).join(", ")}" unless unknown.empty?
      end
      private_class_method :check_constraint_keys!

      # Raises when an :enum field has no non-empty list of allowed values.
      #
      # @param name [Symbol, String] field identifier, used in the message
      # @param type [Symbol] field type
      # @param allowed [Object] the :allowed_values constraint
      # @return [void]
      # @raise [Error] with code :invalid_flow when an :enum field lacks allowed values
      def self.check_enum_values!(name, type, allowed)
        return unless type == :enum && (!allowed.is_a?(Array) || allowed.empty?)

        raise Error.new(:invalid_flow, "Enum field #{name} requires a non-empty :in list")
      end

      # Validates and coerces an input value.
      #
      # @param raw_value [Object] untrusted value from submitted params
      # @return [Array(Object, Array<String>)] pair of [coerced_value, error_codes]
      def validate(raw_value)
        return [nil, @required ? ["required"] : []] if blank_value?(raw_value)

        method(VALIDATORS.fetch(@type)).call(raw_value)
      end

      private

      def blank_value?(val)
        val.nil? || (val.is_a?(String) && val.strip.empty?)
      end

      def validate_string(val)
        str = val.to_s
        return [nil, ["too_long"]] if str.length > MAX_STRING_LENGTH

        [str, []]
      end

      def validate_email(val)
        str = val.to_s
        return [nil, ["invalid_email"]] if str.length > MAX_EMAIL_LENGTH
        return [nil, ["invalid_email"]] if str.match?(/\s/)

        parts = str.split("@", -1)
        return [nil, ["invalid_email"]] unless parts.length == 2
        return [nil, ["invalid_email"]] if parts[0].empty? || parts[1].empty?

        [str, []]
      end

      def validate_integer(val)
        int_val = parse_integer(val)
        return [nil, ["not_an_integer"]] if int_val.nil?
        return [nil, ["out_of_range"]] if (!@min.nil? && int_val < @min) || (!@max.nil? && int_val > @max)

        [int_val, []]
      end

      def parse_integer(val)
        return val if val.is_a?(Integer)
        return nil unless val.is_a?(String) && val.match?(/\A-?\d+\z/)

        Integer(val, 10)
      end

      def validate_boolean(val)
        case val
        when true, "true" then [true, []]
        when false, "false" then [false, []]
        else [nil, ["not_a_boolean"]]
        end
      end

      def validate_enum(val)
        str = val.to_s
        return [nil, ["not_in_list"]] unless @allowed_values.include?(str)

        [str, []]
      end
    end
  end
end
