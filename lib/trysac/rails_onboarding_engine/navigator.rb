# frozen_string_literal: true

require_relative "progress"

module Trysac
  module RailsOnboardingEngine
    # Computes how a {Progress} moves through a {Flow}: which steps are visible, which step comes next,
    # which answers survive a branch change, and the completion percentage. It never touches storage.
    class Navigator
      # Bound flow definition.
      # @return [Flow]
      attr_reader :flow

      # Initializes a navigator for one flow.
      #
      # @param flow [Flow] onboarding flow definition
      def initialize(flow)
        @flow = flow
      end

      # Returns the current step and percentage of a progress that has not answered anything yet.
      #
      # @return [Hash{Symbol => Object}] `:current_step` (Symbol, nil) and `:percent` (Integer)
      def initial_position
        visible = @flow.visible_steps({})
        { current_step: visible.first&.name, percent: percent(visible, []) }
      end

      # Records the coerced answers of a step and moves to the next visible, unanswered step.
      # Answers of steps that the new answers hide are pruned.
      #
      # @param progress [Progress] progress before the submission
      # @param step_name [Symbol] submitted step
      # @param answers [Hash{Symbol => Object}] coerced answers of that step
      # @return [Progress] the advanced progress (not saved)
      def advance(progress, step_name, answers)
        visible, step_data, data = resolve_visibility(progress.step_data.merge(step_name => answers))
        names = visible.map(&:name)
        candidates = (progress.completed_steps + [step_name]).uniq
        completed = names.select { |name| candidates.include?(name) }
        next_step = find_next_step(names, step_name, completed)
        progress.with(current_step: next_step, data: data, step_data: step_data, completed_steps: completed,
                      percent: next_step.nil? ? 100 : percent(visible, completed))
      end

      # Moves a progress back to the previous visible step, keeping earlier answers.
      #
      # @param progress [Progress] an incomplete progress
      # @return [Progress] the same object when already on the first visible step, otherwise the moved progress
      def back(progress)
        visible = @flow.visible_steps(progress.data)
        names = visible.map(&:name)
        index = names.index(progress.current_step) || 0
        return progress if index <= 0

        previous = names[index - 1]
        completed = progress.completed_steps.reject { |name| name == previous }
        progress.with(current_step: previous, completed_steps: completed, percent: percent(visible, completed))
      end

      # Computes the completion percentage of the completed steps among the visible steps, rounded down.
      #
      # @param visible [Array<Step>] currently visible steps
      # @param completed_names [Array<Symbol>] completed step names
      # @return [Integer] 0..100, and 100 when no step is visible
      def percent(visible, completed_names)
        return 100 if visible.empty?

        names = visible.map(&:name)
        done = completed_names.count { |name| names.include?(name) }
        (100 * done) / visible.size
      end

      private

      def resolve_visibility(raw_step_data)
        step_data = {}
        data = {}
        visible = @flow.steps.select do |step|
          next false unless step.visible?(data)

          answers = raw_step_data[step.name]
          data.merge!(step_data[step.name] = answers) if raw_step_data.key?(step.name)
          true
        end
        [visible, step_data, data]
      end

      def find_next_step(names, submitted_step, completed)
        index = names.index(submitted_step)
        after = index ? names[(index + 1)..].find { |name| !completed.include?(name) } : nil
        after || names.find { |name| !completed.include?(name) }
      end
    end
  end
end
