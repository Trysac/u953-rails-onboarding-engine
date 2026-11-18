# frozen_string_literal: true

require "securerandom"
require_relative "clock"
require_relative "progress"
require_relative "result"
require_relative "token_codec"
require_relative "navigator"
require_relative "migrator"

module Trysac
  module RailsOnboardingEngine
    # Coordinates multi-step flow execution, branching, progress calculation,
    # version migrations, persistence, callbacks, and resume tokens.
    class Engine
      # Default resume token time-to-live in seconds (7 days).
      DEFAULT_TOKEN_TTL = 604_800

      # Maximum number of keys allowed in submitted step params.
      MAX_PARAM_KEYS = 64

      # Maximum character length of any single submitted parameter value.
      MAX_PARAM_VALUE_LENGTH = 10_000

      # Maximum length of subject_id.
      MAX_SUBJECT_ID_LENGTH = 256

      # Optional keywords accepted by {#initialize}.
      OPTIONS = %i[clock token_ttl on_complete on_event].freeze

      # Bound Flow definition.
      # @return [Flow]
      attr_reader :flow

      # Persistence store.
      # @return [#fetch, #save]
      attr_reader :store

      # Clock used for token timestamps.
      # @return [#now]
      attr_reader :clock

      # Token TTL in seconds.
      # @return [Integer]
      attr_reader :token_ttl

      # Initializes a new Engine.
      #
      # @param flow [Flow] onboarding flow definition
      # @param store [#fetch, #save] progress storage adapter
      # @param secret [String] HMAC secret of at least 32 bytes
      # @param options [Hash] optional collaborators and callbacks
      # @option options [#now] :clock clock object (defaults to Clock.new)
      # @option options [Integer] :token_ttl resume token lifetime in seconds (default 604_800)
      # @option options [Proc, nil] :on_complete callback invoked once with final data when flow completes
      # @option options [Proc, nil] :on_event callback invoked with {type:, flow:, step:} events
      # @raise [Error] with code :invalid_flow if configuration is invalid
      # @raise [ArgumentError] when an unknown option is given
      def initialize(flow:, store:, secret:, **options)
        self.class.check_config!(flow, store, options)
        @flow = flow
        @store = store
        @clock = options.fetch(:clock) { Clock.new }
        @secret = TokenCodec.validate_secret!(secret)
        @token_ttl = options.fetch(:token_ttl, DEFAULT_TOKEN_TTL)
        @on_complete = options[:on_complete]
        @on_event = options[:on_event]
        @navigator = Navigator.new(flow)
        @migrator = Migrator.new(@navigator)
      end

      # Raises unless the flow, store and options form a valid engine configuration.
      #
      # @param flow [Object] candidate flow
      # @param store [Object] candidate store
      # @param options [Hash{Symbol => Object}] options passed to {#initialize}
      # @return [void]
      # @raise [Error] with code :invalid_flow if configuration is invalid
      # @raise [ArgumentError] when an unknown option is given
      def self.check_config!(flow, store, options)
        unknown = options.keys - OPTIONS
        raise ArgumentError, "unknown keywords: #{unknown.map(&:inspect).join(", ")}" unless unknown.empty?
        raise Error.new(:invalid_flow, "flow must be a Flow") unless flow.is_a?(Flow)
        unless store.respond_to?(:fetch) && store.respond_to?(:save)
          raise Error.new(:invalid_flow, "store must respond to :fetch and :save")
        end

        check_token_ttl!(options.fetch(:token_ttl, DEFAULT_TOKEN_TTL))
      end

      # Raises unless the resume token lifetime is a positive Integer.
      #
      # @param ttl [Object] candidate lifetime in seconds
      # @return [void]
      # @raise [Error] with code :invalid_flow when the lifetime is not a positive Integer
      def self.check_token_ttl!(ttl)
        raise Error.new(:invalid_flow, "token_ttl must be positive") unless ttl.is_a?(Integer) && ttl.positive?
      end

      # Starts a new onboarding progress for the given subject.
      #
      # @param subject_id [String, Symbol, Integer] identifier of the user or entity
      # @return [Progress] newly initialized and saved Progress
      def start(subject_id)
        subj = subject_id.to_s
        raise Error.new(:payload_too_large, "subject_id is too long") if subj.length > MAX_SUBJECT_ID_LENGTH

        progress = Progress.new(id: SecureRandom.uuid, subject_id: subj, flow_name: @flow.name, version: @flow.version,
                                data: {}, step_data: {}, completed_steps: [], **@navigator.initial_position)
        @store.save(progress)
      end

      # Loads a Progress by id, applying any configured version migrations if needed.
      #
      # @param progress_id [String] progress id
      # @return [Progress]
      # @raise [Error] with code :not_found or :version_mismatch
      def load(progress_id)
        progress = @store.fetch(progress_id)
        raise Error.new(:version_mismatch, "Flow name mismatch") unless progress.flow_name == @flow.name

        migrated = @migrator.migrate(progress)
        migrated.equal?(progress) ? progress : @store.save(migrated)
      end

      # Submits answers for the current step.
      #
      # @param progress_id [String] progress identifier
      # @param step [Symbol, String] step name being submitted
      # @param params [Hash] field answers
      # @return [Result] validation result and updated progress
      # @raise [Error] with codes :not_found, :already_completed, :unknown_step, :wrong_step, :payload_too_large
      def submit(progress_id, step, params)
        enforce_payload_limits!(params)
        progress = load(progress_id)
        step_def = submittable_step!(progress, step)
        coerced, errors = step_def.validate(params)
        return Result.new(success: false, progress: progress, errors: errors) unless errors.empty?

        updated = @navigator.advance(progress, step_def.name, coerced)
        @store.save(updated)
        notify_submitted(updated, step_def.name)
        Result.new(success: true, progress: updated, errors: {})
      end

      # Moves the progress back to the previous visible step, keeping earlier answers.
      #
      # @param progress_id [String] progress identifier
      # @return [Progress] updated progress
      # @raise [Error] with code :already_completed if already finished
      def back(progress_id)
        progress = load(progress_id)
        raise Error.new(:already_completed, "Cannot go back on a completed flow") if progress.complete?

        moved = @navigator.back(progress)
        moved.equal?(progress) ? progress : @store.save(moved)
      end

      # Generates an HMAC-SHA256 signed resume token for the given progress.
      #
      # @param progress [Progress] progress instance
      # @return [String] signed token
      def resume_token(progress)
        expires_at = @clock.now.to_i + @token_ttl
        TokenCodec.encode(progress: progress, secret: @secret, expires_at: expires_at)
      end

      # Verifies a resume token, loads and migrates the progress, and emits a :resumed event.
      #
      # @param token [String] signed resume token
      # @return [Progress]
      # @raise [Error] with codes :invalid_token, :token_expired, :not_found, :version_mismatch
      def resume(token)
        claims = TokenCodec.decode_and_verify(token: token, secret: @secret, expected_flow: @flow.name,
                                              now_epoch: @clock.now.to_i)
        progress = load(claims["p"])
        emit_event(:resumed, progress.current_step)
        progress
      end

      private

      def enforce_payload_limits!(params)
        raise Error.new(:payload_too_large, "Params must be a Hash") unless params.is_a?(Hash)

        too_many = params.size > MAX_PARAM_KEYS
        raise Error.new(:payload_too_large, "Too many parameter keys (max #{MAX_PARAM_KEYS})") if too_many
        return unless params.each_value.any? { |val| val.is_a?(String) && val.length > MAX_PARAM_VALUE_LENGTH }

        raise Error.new(:payload_too_large, "Parameter value exceeds #{MAX_PARAM_VALUE_LENGTH} characters")
      end

      def submittable_step!(progress, step)
        raise Error.new(:already_completed, "Flow is already completed") if progress.complete?

        step_sym = step.to_sym
        step_def = @flow.find_step(step_sym)
        raise Error.new(:unknown_step, "Unknown step: #{step_sym}") if step_def.nil?
        return step_def if progress.current_step == step_sym

        raise Error.new(:wrong_step, "Expected step #{progress.current_step}, got #{step_sym}")
      end

      def notify_submitted(progress, step_name)
        emit_event(:step_completed, step_name)
        return unless progress.complete?

        emit_event(:completed, step_name)
        @on_complete&.call(progress.data)
      end

      def emit_event(type, step_name)
        @on_event&.call({ type: type, flow: @flow.name, step: step_name })
      end
    end
  end
end
