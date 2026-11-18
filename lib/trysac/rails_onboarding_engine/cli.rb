# frozen_string_literal: true

require "json"
require_relative "version"
require_relative "error"

module Trysac
  module RailsOnboardingEngine
    # Command-line interface for inspecting or simulating an onboarding flow from JSON.
    module CLI
      # Exit code for successful execution.
      EXIT_OK = 0

      # Exit code for domain or validation failures.
      EXIT_DOMAIN_ERROR = 1

      # Exit code for usage, IO, or JSON parse errors.
      EXIT_USAGE_ERROR = 2

      # Arguments that print the usage text.
      HELP_FLAGS = %w[--help -h].freeze

      # Arguments that print the gem version.
      VERSION_FLAGS = %w[--version -v].freeze

      # Runs the CLI with the provided argument vector and output streams.
      #
      # @param argv [Array<String>] command-line arguments
      # @param stdout [IO] standard output stream
      # @param stderr [IO] standard error stream
      # @return [Integer] exit code (0 ok, 1 domain failure, 2 usage/parse error)
      def self.run(argv, stdout: $stdout, stderr: $stderr)
        dispatch(Array(argv).map(&:to_s), stdout, stderr)
      rescue JSON::ParserError, Errno::ENOENT, Errno::EACCES => e
        stderr.puts("IO/Parse error: #{e.message[0, 200]}")
        EXIT_USAGE_ERROR
      rescue Error => e
        stderr.puts("Domain error (#{e.code}): #{e.message}")
        EXIT_DOMAIN_ERROR
      end

      # Declares the fields of a JSON flow specification on a step builder.
      #
      # @param builder [Step::Builder] builder of the step being defined
      # @param field_specs [Array<Hash{String => Object}>] field specifications (`name`, `type`, `required`, `in`,
      #   `min`, `max`)
      # @return [void]
      # @raise [KeyError] when a field has no name
      def self.add_fields(builder, field_specs)
        field_specs.each do |spec|
          builder.field(spec.fetch("name"), type: (spec["type"] || "string").to_sym,
                                            required: spec.fetch("required", false),
                                            in: spec["in"], min: spec["min"], max: spec["max"])
        end
      end

      def self.dispatch(args, stdout, stderr)
        return print_help(stdout) if args.empty? || args.intersect?(HELP_FLAGS)
        return print_version(stdout) if args.intersect?(VERSION_FLAGS)
        return run_simulate(args[1..], stdout: stdout, stderr: stderr) if args.first == "simulate"

        stderr.puts("Unknown command: #{args.first}")
        EXIT_USAGE_ERROR
      end

      def self.print_help(stdout)
        stdout.puts("Usage: rails_onboarding_engine [simulate <json_payload> | --version | --help]")
        EXIT_OK
      end

      def self.print_version(stdout)
        stdout.puts(VERSION)
        EXIT_OK
      end

      def self.run_simulate(rest, stdout:, stderr:)
        return missing_payload(stderr) if rest.nil? || rest.empty?

        spec = parse_spec(rest.first)
        progress = submit_all(simulation_engine(spec), spec, stdout)
        return EXIT_DOMAIN_ERROR if progress.nil?

        stdout.puts(JSON.generate(progress.to_h.merge("ok" => true)))
        EXIT_OK
      end

      def self.parse_spec(json)
        spec = JSON.parse(json)
        raise JSON::ParserError, "Expected JSON object" unless spec.is_a?(Hash)

        spec
      end

      def self.missing_payload(stderr)
        stderr.puts("Missing JSON payload for simulate")
        EXIT_USAGE_ERROR
      end

      def self.simulation_engine(spec)
        Engine.new(flow: build_flow_from_spec(spec), store: MemoryStore.new,
                   secret: "cli-simulation-default-secret-32b!")
      end

      # Starts a progress and submits every step in order; prints the errors and returns nil on the first failure.
      def self.submit_all(engine, spec, stdout)
        progress = engine.start(spec["subject_id"] || "sim-user")
        Array(spec["submissions"]).each do |sub|
          res = engine.submit(progress.id, sub.fetch("step"), sub.fetch("params", {}))
          return report_failure(res, stdout) unless res.ok?

          progress = res.progress
        end
        progress
      end

      def self.report_failure(res, stdout)
        stdout.puts(JSON.generate({ "ok" => false, "errors" => res.errors, "step" => res.progress.current_step }))
        nil
      end

      def self.build_flow_from_spec(spec)
        steps_spec = Array(spec["steps"])
        Flow.define(spec["flow"] || "default", version: Integer(spec["version"] || 1)) do
          steps_spec.each do |s|
            step(s.fetch("name")) { CLI.add_fields(self, Array(s["fields"])) }
          end
        end
      end

      private_class_method :dispatch, :print_help, :print_version, :run_simulate, :parse_spec, :missing_payload,
                           :simulation_engine, :submit_all, :report_failure, :build_flow_from_spec
    end
  end
end
