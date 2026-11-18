# frozen_string_literal: true

require "spec_helper"

require "stringio"
require "json"

RSpec.describe Trysac::RailsOnboardingEngine::CLI do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }
  let(:account_steps) do
    [{ "name" => "account", "fields" => [{ "name" => "email", "type" => "email", "required" => true }] }]
  end

  def run_cli(*args)
    described_class.run(args, stdout: out, stderr: err)
  end

  def simulate(spec)
    run_cli("simulate", JSON.generate(spec))
  end

  it "prints help with exit code 0" do
    expect(run_cli("--help")).to eq(0)
    expect(out.string).to include("Usage:")
  end

  it "prints the version with exit code 0" do
    expect(run_cli("--version")).to eq(0)
    expect(out.string.strip).to eq(Trysac::RailsOnboardingEngine::VERSION)
  end

  it "simulates a valid onboarding run from JSON and exits 0" do
    code = simulate("flow" => "cli_flow", "version" => 1, "subject_id" => "user-cli", "steps" => account_steps,
                    "submissions" => [{ "step" => "account", "params" => { "email" => "ada@example.test" } }])
    parsed = JSON.parse(out.string)
    expect(code).to eq(0)
    expect(parsed.values_at("ok", "percent")).to eq([true, 100])
  end

  it "returns exit code 1 on validation errors" do
    code = simulate("flow" => "cli_flow", "steps" => account_steps,
                    "submissions" => [{ "step" => "account", "params" => { "email" => "nope" } }])
    expect(code).to eq(1)
  end

  it "returns exit code 1 on domain failures such as a flow without steps" do
    expect(simulate("flow" => "empty", "steps" => [])).to eq(1)
  end

  it "returns exit code 2 on unknown commands, missing args, or malformed JSON" do
    expect(run_cli("unknown")).to eq(2)
    expect(run_cli("simulate")).to eq(2)
    expect(run_cli("simulate", "{not-json")).to eq(2)
  end
end
