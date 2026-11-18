# u953-rails-onboarding-engine

Multi-step onboarding flow engine with a declarative step DSL, conditional branches, progress percentages, versioned migrations and HMAC-signed resume tokens.

## Why

Product teams often build signup and onboarding wizards by hand in controllers. Users who leave halfway lose their answers or return to a step that no longer exists after a release, and conditional steps make naive progress bars jump inaccurately. `Trysac::RailsOnboardingEngine` defines flows as immutable data with validations and visibility conditions, computes progress percentages strictly over the steps that apply, persists state behind a clean store interface, and lets users safely resume via HMAC-SHA256 signed tokens without requiring Rails at test or domain time.

## Installation

```bash
bundle add u953-rails-onboarding-engine
```

## Usage

```ruby
require "trysac/rails_onboarding_engine"

flow = Trysac::RailsOnboardingEngine::Flow.define(:signup, version: 1) do
  step(:account) { field :email, type: :email, required: true }
  step(:plan)    { field :plan, type: :enum, in: %w[free pro], required: true }
end
engine = Trysac::RailsOnboardingEngine::Engine.new(
  flow: flow, store: Trysac::RailsOnboardingEngine::MemoryStore.new, secret: ENV.fetch("ONBOARDING_SECRET")
)
progress = engine.start("user-42")
result = engine.submit(progress.id, :account, { email: "ada@example.test" })
```

## Features

- **Declarative DSL (`Flow.define`)**: Define steps, typed fields (`:string`, `:email`, `:integer`, `:boolean`, `:enum`), visibility predicates (`if: ->(data) { ... }`), and sequential version migrations (`migrate(from: 1)`).
- **Branch-Aware Progress**: Calculates `percent = floor(100 * completed_visible_steps / visible_steps)` dynamically and prunes stored answers belonging to steps that become invisible when an earlier answer changes.
- **HMAC-SHA256 Resume Tokens**: Base64url-encoded JSON claims (`f`, `p`, `v`, `e`) signed with RFC 2104 HMAC-SHA256 and verified using `OpenSSL.fixed_length_secure_compare` before parsing. Tokens never contain user answers.
- **Pluggable Storage**: Includes `MemoryStore` (bounded with `max_entries: 10_000`) and `JsonFileStore` (atomic write-to-temp then `File.rename`).

## Development

```bash
bundle install
ruby scripts/check.rb
```

## License

MIT
