# frozen_string_literal: true

require_relative "step"

module Trysac
  module RailsOnboardingEngine
    # Immutable definition of a multi-step onboarding flow, its steps, and version migrations.
    class Flow
      # Flow identifier.
      # @return [String]
      attr_reader :name

      # Schema version of this flow.
      # @return [Integer]
      attr_reader :version

      # Ordered list of steps.
      # @return [Array<Step>]
      attr_reader :steps

      # Map of migration blocks keyed by source version.
      # @return [Hash{Integer => Proc}]
      attr_reader :migrations

      # DSL builder for Flow.define.
      class Builder
        # Initializes the flow builder.
        def initialize
          @steps = []
          @step_names = {}
          @migrations = {}
        end

        # Defines a step in the flow.
        #
        # @param name [Symbol, String] unique step name
        # @param opts [Hash] options such as :if callable
        # @yield [Step::Builder] DSL block for step fields
        # @return [Step]
        def step(name, **opts, &)
          Flow.check_name!(name, "Step name cannot be empty")
          sym = name.to_sym
          raise Error.new(:invalid_flow, "Duplicate step: #{sym}") if @step_names.key?(sym)

          new_step = Step.new(sym, condition: opts[:if], fields: step_fields(&))
          @step_names[sym] = true
          @steps << new_step
          new_step
        end

        # Defines a migration from an earlier flow version.
        #
        # @param from [Integer] source version number
        # @yieldparam data [Hash{Symbol => Object}] collected data to transform
        # @yieldreturn [Hash{Symbol => Object}] migrated data
        # @return [void]
        def migrate(from:, &block)
          raise Error.new(:invalid_flow, "Migration requires a block") unless block
          unless Flow.positive_integer?(from)
            raise Error.new(:invalid_flow, "Migration :from must be a positive Integer")
          end

          @migrations[from] = block
        end

        # Builds the step list.
        # @return [Array<Step>]
        def build_steps
          @steps.dup.freeze
        end

        # Builds the migrations map.
        # @return [Hash{Integer => Proc}]
        def build_migrations
          @migrations.dup.freeze
        end

        private

        def step_fields(&block)
          step_builder = Step::Builder.new
          step_builder.instance_exec(&block) if block
          step_builder.build_fields
        end
      end

      # Defines and freezes a new Flow using the declarative DSL.
      #
      # @param name [Symbol, String] flow name
      # @param version [Integer] flow version (default 1)
      # @yield [Builder] DSL block
      # @return [Flow] frozen Flow instance
      # @raise [Error] with code :invalid_flow if definition is invalid
      def self.define(name, version: 1, &block)
        check_name!(name, "Flow name cannot be blank")
        raise Error.new(:invalid_flow, "Flow version must be a positive Integer") unless positive_integer?(version)

        builder = Builder.new
        builder.instance_exec(&block) if block
        steps = builder.build_steps
        raise Error.new(:invalid_flow, "Flow must define at least one step") if steps.empty?

        new(name: name.to_s, version: version, steps: steps, migrations: builder.build_migrations)
      end

      # Raises an :invalid_flow error when a flow or step name is nil or blank.
      #
      # @param name [Symbol, String, nil] the name to check
      # @param message [String] error message used when the name is blank
      # @return [void]
      # @raise [Error] with code :invalid_flow when the name is blank
      def self.check_name!(name, message)
        raise Error.new(:invalid_flow, message) if name.nil? || name.to_s.strip.empty?
      end

      # Tells whether a value is a positive Integer, as flow versions and migration sources must be.
      #
      # @param value [Object] the value to check
      # @return [Boolean]
      def self.positive_integer?(value)
        value.is_a?(Integer) && value.positive?
      end

      # Initializes a Flow instance.
      #
      # @param name [String] flow name
      # @param version [Integer] flow version
      # @param steps [Array<Step>] ordered steps
      # @param migrations [Hash{Integer => Proc}] migration blocks
      def initialize(name:, version:, steps:, migrations: {})
        @name = name.to_s.freeze
        @version = version
        @steps = steps.dup.freeze
        @step_index = @steps.to_h { |s| [s.name, s] }.freeze
        @migrations = migrations.dup.freeze
        freeze
      end

      # Looks up a step by name.
      #
      # @param step_name [Symbol, String] step name
      # @return [Step, nil]
      def find_step(step_name)
        return nil if step_name.nil?

        @step_index[step_name.to_sym]
      end

      # Returns the ordered list of currently visible steps for the given data.
      #
      # @param data [Hash{Symbol => Object}] collected answers
      # @return [Array<Step>]
      def visible_steps(data)
        @steps.select { |s| s.visible?(data) }
      end
    end
  end
end
