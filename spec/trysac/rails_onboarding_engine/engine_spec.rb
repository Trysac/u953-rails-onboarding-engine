# frozen_string_literal: true

require "spec_helper"

require "tmpdir"

RSpec.describe Trysac::RailsOnboardingEngine::Engine do
  let(:secret) { "0123456789abcdef0123456789abcdef" }
  let(:clock) { Trysac::RailsOnboardingEngine::FrozenClock.new(Time.utc(2025, 1, 1, 12, 0, 0)) }
  let(:recorded) { { events: [], completions: [] } }
  let(:engine) do
    engine_for(onboarding_flow, on_complete: ->(data) { recorded[:completions] << data },
                                on_event: ->(ev) { recorded[:events] << ev })
  end

  let(:onboarding_flow) do
    Trysac::RailsOnboardingEngine::Flow.define(:signup, version: 1) do
      step(:account) do
        field :email, type: :email, required: true
        field :account_type, type: :enum, in: %w[personal business], required: true
      end

      step(:profile) do
        field :name, type: :string, required: true
      end

      step(:company, if: ->(data) { data[:account_type] == "business" }) do
        field :company_name, type: :string, required: true
        field :seats, type: :integer, min: 1, max: 500, required: false
      end

      step(:plan) do
        field :plan, type: :enum, in: %w[free pro], required: true
        field :newsletter, type: :boolean, required: false
      end
    end
  end

  def engine_for(flow, store: Trysac::RailsOnboardingEngine::MemoryStore.new, **)
    described_class.new(flow: flow, store: store, clock: clock, secret: secret, **)
  end

  def account(type = "personal")
    { email: "ada@example.test", account_type: type }
  end

  # Starts a progress and submits valid answers until it reaches the given step.
  def advance_to(step_name, type: "business")
    answers = { account: account(type), profile: { name: "Ada Lovelace" },
                company: { company_name: "Babbage Engines", seats: 10 } }
    progress = engine.start("user")
    progress = engine.submit(progress.id, progress.current_step, answers.fetch(progress.current_step)).progress until
      progress.current_step == step_name
    progress
  end

  def submit_at(step_name, params, type: "business")
    engine.submit(advance_to(step_name, type: type).id, step_name, params)
  end

  describe "branching progress and step transitions" do
    it "starts on the first step at 0% and incomplete" do
      started = engine.start("user-1")
      expect([started.current_step, started.percent, started.complete?]).to eq([:account, 0, false])
    end

    it "computes percent over the three visible steps of the personal branch" do
      res = engine.submit(engine.start("user-1").id, :account, account("personal"))
      expect([res.ok?, res.progress.current_step, res.progress.percent]).to eq([true, :profile, 33])
    end

    it "computes percent over the four visible steps of the business branch" do
      res = engine.submit(engine.start("user-2").id, :account, account("business"))
      expect([res.ok?, res.progress.current_step, res.progress.percent]).to eq([true, :profile, 25])
    end
  end

  describe "field validations and unknown key filtering" do
    it "returns invalid_email and stays on the step" do
      res = submit_at(:account, { email: "nope", account_type: "personal" })
      expect([res.ok?, res.errors, res.progress.current_step]).to eq([false, { email: ["invalid_email"] }, :account])
    end

    it "returns required for a blank required field" do
      res = submit_at(:account, { email: "", account_type: "personal" })
      expect([res.ok?, res.errors]).to eq([false, { email: ["required"] }])
    end

    it "drops unknown keys" do
      res = submit_at(:account, { "email" => "ada@example.test", "account_type" => "personal", "extra_hack" => "x" })
      expect(res.ok?).to be(true)
      expect(res.progress.data).to eq({ email: "ada@example.test", account_type: "personal" })
    end

    it "returns not_in_list for a value outside an enum" do
      res = submit_at(:plan, { plan: "gold" }, type: "personal")
      expect([res.ok?, res.errors]).to eq([false, { plan: ["not_in_list"] }])
    end

    it "returns too_long for a string over 200 characters" do
      res = submit_at(:profile, { name: "x" * 201 })
      expect([res.ok?, res.errors]).to eq([false, { name: ["too_long"] }])
    end

    it "returns not_an_integer and out_of_range for bad integers" do
      expect(submit_at(:company, { company_name: "Analytical", seats: "twelve" }).errors)
        .to eq({ seats: ["not_an_integer"] })
      expect(submit_at(:company, { company_name: "Analytical", seats: 0 }).errors).to eq({ seats: ["out_of_range"] })
    end

    it "coerces an integer string" do
      res = submit_at(:company, { company_name: "Analytical", seats: "42" })
      expect([res.ok?, res.progress.data[:seats]]).to eq([true, 42])
    end

    it "returns not_a_boolean for a bad boolean and coerces \"true\"" do
      expect(submit_at(:plan, { plan: "pro", newsletter: "maybe" }).errors).to eq({ newsletter: ["not_a_boolean"] })
      res = submit_at(:plan, { plan: "pro", newsletter: "true" })
      expect([res.ok?, res.progress.data[:newsletter]]).to eq([true, true])
    end
  end

  describe "resume tokens" do
    def after_account
      engine.submit(engine.start("user-resume").id, :account, account).progress
    end

    it "does not carry answers inside the token" do
      expect(engine.resume_token(after_account)).not_to include("ada@example.test")
    end

    it "resumes 6 days after issuance and emits :resumed" do
      progress = after_account
      token = engine.resume_token(progress)
      clock.advance(6 * 86_400)
      resumed = engine.resume(token)
      expect([resumed, resumed.current_step]).to eq([progress, :profile])
      expect(recorded[:events].last).to eq({ type: :resumed, flow: "signup", step: :profile })
    end

    it "rejects a token 7 days plus 1 second after issuance with :token_expired" do
      token = engine.resume_token(after_account)
      clock.advance((7 * 86_400) + 1)
      expect { engine.resume(token) }.to raise_engine_error(:token_expired)
    end

    it "rejects a tampered signature with :invalid_token" do
      token = engine.resume_token(after_account)
      tampered = "#{token[0...-1]}#{token[-1] == "A" ? "B" : "A"}"
      expect { engine.resume(tampered) }.to raise_engine_error(:invalid_token)
    end

    it "rejects a token issued for another flow with :invalid_token" do
      other_flow = Trysac::RailsOnboardingEngine::Flow.define(:other_wizard) do
        step(:account) { field :email, type: :email, required: true }
      end
      other_engine = engine_for(other_flow, store: engine.store)
      other_token = other_engine.resume_token(other_engine.start("user-other"))
      expect { engine.resume(other_token) }.to raise_engine_error(:invalid_token)
    end
  end

  describe "back navigation and pruning invisible step data" do
    it "returns to the previous step with earlier answers kept" do
      progress = engine.submit(engine.start("user-branch").id, :account, account("business")).progress
      back_to_account = engine.back(progress.id)
      expect([back_to_account.current_step, back_to_account.data]).to eq([:account, account("business")])
    end

    it "keeps the business branch answers on the way to the plan step" do
      at_plan = advance_to(:plan)
      expect([at_plan.current_step, at_plan.data[:company_name]]).to eq([:plan, "Babbage Engines"])
    end

    it "walks back from plan to account through company and profile" do
      progress = advance_to(:plan)
      expect(Array.new(3) { engine.back(progress.id).current_step }).to eq(%i[company profile account])
    end

    it "removes the hidden branch's answers after switching to personal" do
      progress = advance_to(:plan)
      3.times { engine.back(progress.id) }
      switched = engine.submit(progress.id, :account, account("personal")).progress
      expect(switched.data.keys & %i[company_name seats]).to be_empty
      expect(switched.completed_steps).not_to include(:company)
      expect(onboarding_flow.visible_steps(switched.data).map(&:name)).to eq(%i[account profile plan])
    end
  end

  describe "full end-to-end flow completion and callbacks" do
    def complete_personal
      progress = advance_to(:plan, type: "personal")
      engine.submit(progress.id, :plan, { plan: "free", newsletter: false }).progress
    end

    it "is at 66% on the plan step of the personal branch" do
      expect(advance_to(:plan, type: "personal").percent).to eq(66)
    end

    it "completes the flow at 100% with no current step" do
      final = complete_personal
      expect([final.complete?, final.current_step, final.percent]).to eq([true, nil, 100])
    end

    it "runs on_complete once with the collected data" do
      complete_personal
      expect(recorded[:completions]).to eq(
        [{ email: "ada@example.test", account_type: "personal", name: "Ada Lovelace", plan: "free", newsletter: false }]
      )
    end

    it "emits events without answer values" do
      complete_personal
      expect(recorded[:events]).to eq(
        [{ type: :step_completed, flow: "signup", step: :account },
         { type: :step_completed, flow: "signup", step: :profile },
         { type: :step_completed, flow: "signup", step: :plan },
         { type: :completed, flow: "signup", step: :plan }]
      )
    end

    it "blocks extra submits and back navigation with :already_completed" do
      final = complete_personal
      expect { engine.submit(final.id, :plan, { plan: "pro" }) }.to raise_engine_error(:already_completed)
      expect { engine.back(final.id) }.to raise_engine_error(:already_completed)
    end

    it "raises :unknown_step and :wrong_step when steps are submitted out of order" do
      started = engine.start("user-order")
      expect { engine.submit(started.id, :nonexistent, { email: "ada@example.test" }) }
        .to raise_engine_error(:unknown_step)
      expect { engine.submit(started.id, :plan, { plan: "free" }) }.to raise_engine_error(:wrong_step)
    end
  end

  describe "versioned flow migrations" do
    def flow_v2(runs)
      Trysac::RailsOnboardingEngine::Flow.define(:signup, version: 2) do
        step(:account) do
          field :email, type: :email, required: true
          field :account_type, type: :enum, in: %w[personal business], required: true
        end
        step(:profile) { field :name, type: :string, required: true }
        step(:plan) { field :plan, type: :enum, in: %w[free pro], required: true }
        migrate(from: 1) { |data| runs.push(:ran) && data.merge(email: data[:email].downcase) }
      end
    end

    def stored_v1_id
      engine.submit(engine.start("user-mig").id, :account, account).progress.id
    end

    it "runs migrate(from: 1) once when v2 loads a v1 progress" do
      runs = []
      loaded = engine_for(flow_v2(runs), store: engine.store).load(stored_v1_id)
      expect([loaded.version, runs.size]).to eq([2, 1])
    end

    it "does not re-run the v1 -> v2 migration on a second load" do
      runs = []
      id = stored_v1_id
      engine_v2 = engine_for(flow_v2(runs), store: engine.store)
      engine_v2.load(id)
      expect([engine_v2.load(id).version, runs.size]).to eq([2, 1])
    end

    it "raises :version_mismatch when a migration is missing" do
      flow_v3 = Trysac::RailsOnboardingEngine::Flow.define(:signup, version: 3) do
        step(:account) { field :email, type: :email, required: true }
      end
      id = stored_v1_id
      expect { engine_for(flow_v3, store: engine.store).load(id) }.to raise_engine_error(:version_mismatch)
    end
  end

  describe "payload limits, store capacity, and JsonFileStore round-trip" do
    def build_progress(index)
      Trysac::RailsOnboardingEngine::Progress.new(
        id: "id-#{index}", subject_id: "sub-#{index}", flow_name: "signup", version: 1,
        current_step: :account, data: {}, completed_steps: [], percent: 0
      )
    end

    def full_store
      Trysac::RailsOnboardingEngine::MemoryStore.new(max_entries: 10_000).tap do |bounded|
        10_000.times { |i| bounded.save(build_progress(i)) }
      end
    end

    it "raises :payload_too_large when params have more than 64 keys" do
      sixty_five_keys = (1..65).to_h { |i| [:"k#{i}", "v"] }
      expect { submit_at(:account, sixty_five_keys) }.to raise_engine_error(:payload_too_large)
    end

    it "raises :payload_too_large when a value is over 10_000 characters" do
      expect { submit_at(:account, account.merge(email: "a" * 10_001)) }.to raise_engine_error(:payload_too_large)
    end

    it "keeps 10_000 entries in a MemoryStore with max_entries 10_000 and updates an existing one" do
      bounded = full_store
      existing = bounded.fetch("id-0")
      expect(bounded.size).to eq(10_000)
      expect(bounded.save(existing)).to eq(existing)
    end

    it "raises :store_full on entry 10_001 in MemoryStore with max_entries 10_000" do
      bounded = full_store
      expect { bounded.save(build_progress(10_000)) }.to raise_engine_error(:store_full)
    end

    it "round-trips a progress through JsonFileStore with equal attributes" do
      Dir.mktmpdir("onboarding-store") do |dir|
        file_store = Trysac::RailsOnboardingEngine::JsonFileStore.new(dir)
        file_engine = engine_for(onboarding_flow, store: file_store)
        updated = file_engine.submit(file_engine.start("user-json").id, :account, account("business")).progress
        reloaded = file_store.fetch(updated.id)
        expect([reloaded, reloaded.hash]).to eq([updated, updated.hash])
        expect(reloaded.to_h.values_at("id", "flow_name", "version", "current_step", "data", "completed_steps",
                                       "percent"))
          .to eq([updated.id, "signup", 1, "profile", account("business").transform_keys(&:to_s), ["account"], 25])
      end
    end

    it "raises :not_found for a missing id in JsonFileStore" do
      Dir.mktmpdir("onboarding-store") do |dir|
        file_store = Trysac::RailsOnboardingEngine::JsonFileStore.new(dir)
        expect { file_store.fetch("missing-id") }.to raise_engine_error(:not_found)
      end
    end
  end

  describe "flow definition and configuration validation" do
    it "raises :invalid_flow on empty flows" do
      expect { Trysac::RailsOnboardingEngine::Flow.define(:empty_flow) { nil } }.to raise_engine_error(:invalid_flow)
    end

    it "raises :invalid_flow on duplicate steps" do
      expect do
        Trysac::RailsOnboardingEngine::Flow.define(:dup_steps) do
          step(:first) { field :a, type: :string }
          step(:first) { field :b, type: :string }
        end
      end.to raise_engine_error(:invalid_flow)
    end

    it "raises :invalid_flow on unknown field types" do
      expect do
        Trysac::RailsOnboardingEngine::Flow.define(:bad_field) { step(:first) { field :a, type: :currency } }
      end.to raise_engine_error(:invalid_flow)
    end

    it "raises :invalid_flow on short secrets" do
      expect do
        described_class.new(flow: onboarding_flow, store: engine.store, clock: clock, secret: "too-short")
      end.to raise_engine_error(:invalid_flow)
    end

    it "truncates error messages longer than 200 characters" do
      err = Trysac::RailsOnboardingEngine::Error.new(:invalid_flow, "x" * 300)
      expect(err.message.length).to be <= 203
    end
  end
end
