# frozen_string_literal: true

require "json"
require "fileutils"
require "securerandom"
require_relative "progress"

module Trysac
  module RailsOnboardingEngine
    # File-backed store that persists each Progress as JSON using atomic temp-file writes and rename.
    class JsonFileStore
      # Pattern for safe progress identifiers.
      SAFE_ID_PATTERN = /\A[a-zA-Z0-9_-]{1,128}\z/

      # Target storage directory.
      # @return [String]
      attr_reader :dir

      # Initializes a JsonFileStore.
      #
      # @param dir [String] directory path where JSON files will be stored
      def initialize(dir)
        raise Error.new(:invalid_flow, "Directory path cannot be empty") if dir.nil? || dir.to_s.strip.empty?

        @dir = File.expand_path(dir.to_s)
        FileUtils.mkdir_p(@dir)
      end

      # Loads a Progress record from disk by id.
      #
      # @param id [String] progress identifier
      # @return [Progress]
      # @raise [Error] with code :not_found when the file does not exist
      def fetch(id)
        path = file_path_for(id)
        raise Error.new(:not_found, "Progress not found: #{id}") unless File.exist?(path)

        raw = File.read(path)
        parsed = JSON.parse(raw)
        Progress.from_h(parsed)
      rescue Errno::ENOENT
        raise Error.new(:not_found, "Progress not found: #{id}")
      end

      # Atomically persists a Progress record by writing a temporary file and renaming it.
      #
      # @param progress [Progress] progress to save
      # @return [Progress]
      def save(progress)
        target = file_path_for(progress.id)
        tmp_path = File.join(@dir, ".tmp-#{progress.id}-#{SecureRandom.hex(6)}.json")
        payload = JSON.generate(progress.to_h)

        File.write(tmp_path, payload, mode: "w", encoding: "UTF-8")
        File.rename(tmp_path, target)
        progress
      ensure
        FileUtils.rm_f(tmp_path) if tmp_path && File.exist?(tmp_path)
      end

      private

      def file_path_for(id)
        str_id = id.to_s
        raise Error.new(:not_found, "Invalid progress id") unless str_id.match?(SAFE_ID_PATTERN)

        File.join(@dir, "#{str_id}.json")
      end
    end
  end
end
