# frozen_string_literal: true

require_relative "navigator"

module Trysac
  module RailsOnboardingEngine
    # Upgrades a {Progress} saved under an older flow version by running the flow's migrations in order,
    # then rebuilds its per-step answers, completed steps, current step and percentage for the new version.
    class Migrator
      # Initializes a migrator for one flow.
      #
      # @param navigator [Navigator] navigator of the flow to migrate to
      def initialize(navigator)
        @navigator = navigator
        @flow = navigator.flow
      end

      # Migrates a progress to the flow's version.
      #
      # @param progress [Progress] stored progress
      # @return [Progress] the same object when it already has the flow's version, otherwise the migrated progress
      # @raise [Error] with code :version_mismatch when a migration is missing or the progress is newer than the flow
      def migrate(progress)
        return progress if progress.version == @flow.version
        if progress.version > @flow.version
          raise Error.new(:version_mismatch, "Cannot downgrade flow version #{progress.version} to #{@flow.version}")
        end

        rebuild(progress, migrated_data(progress))
      end

      private

      def migrated_data(progress)
        (progress.version...@flow.version).reduce(progress.data.dup) do |data, version|
          migration = @flow.migrations[version]
          if migration.nil?
            raise Error.new(:version_mismatch, "No migration from version #{version} to #{@flow.version}")
          end

          migration.call(data.dup).transform_keys(&:to_sym)
        end
      end

      def rebuild(progress, data)
        visible = @flow.visible_steps(data)
        names = visible.map(&:name)
        completed = names.select { |name| progress.completed_steps.include?(name) }
        current = current_step(progress, names, completed)
        progress.with(version: @flow.version, current_step: current, data: data, step_data: step_data_for(data),
                      completed_steps: completed, percent: current.nil? ? 100 : @navigator.percent(visible, completed))
      end

      def current_step(progress, names, completed)
        return nil if progress.complete?
        return progress.current_step if names.include?(progress.current_step)

        names.find { |name| !completed.include?(name) }
      end

      def step_data_for(data)
        @flow.steps.each_with_object({}) do |step, result|
          answers = step.fields.keys.select { |name| data.key?(name) }.to_h { |name| [name, data[name]] }
          result[step.name] = answers unless answers.empty?
        end
      end
    end
  end
end
