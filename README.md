# rails-onboarding-engine

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/Trysac/u953-rails-onboarding-engine/actions/workflows/ci.yml/badge.svg)](https://github.com/Trysac/u953-rails-onboarding-engine/actions/workflows/ci.yml)

Multi-step onboarding flow engine with a declarative step DSL, conditional branches, progress percentages, versioned migrations and HMAC-signed resume tokens

## Problem

Describe in two or three sentences the concrete problem this utility solves, who hits it, and what
they do today without it. Replace this paragraph when the first real feature lands.

## Install

```ruby
# Gemfile
gem "u953-rails-onboarding-engine"
```

Until it is published on RubyGems, point the Gemfile at a release tag:
`gem "u953-rails-onboarding-engine", git: "https://github.com/Trysac/u953-rails-onboarding-engine", tag: "v0.1.0"`. Requires Ruby 4.0 or newer. No
dependencies outside the Ruby standard library.

## Usage

```ruby
require "trysac/rails_onboarding_engine"

# normalize trims surrounding whitespace and lower-cases the text.
Trysac::RailsOnboardingEngine::Text.normalize("  Hello World ") # => "hello world"

# Blank input is rejected explicitly instead of returning an empty string.
Trysac::RailsOnboardingEngine::Text.normalize("   ") # raises Trysac::RailsOnboardingEngine::BlankInputError ("input is blank")
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md) and [decisions](docs/decisions/)
- [Testing](docs/TESTING.md) and [security](docs/SECURITY.md)
- [Project record](docs/PROJECT.md) and [stack](docs/STACK.md)
- [Changelog](CHANGELOG.md) and [contributing guide](CONTRIBUTING.md)

## License

[MIT](LICENSE) (c) 2026 Miguel Gomez
