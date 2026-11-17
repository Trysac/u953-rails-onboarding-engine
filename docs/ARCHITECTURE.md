# Architecture

## Purpose

The gem `u953-rails-onboarding-engine` is a small, dependency-free Ruby library: Multi-step onboarding flow engine with a declarative step DSL, conditional branches, progress percentages, versioned migrations and HMAC-signed resume tokens

## Shape

```text
caller code --> require "trysac/rails_onboarding_engine" (lib/trysac/rails_onboarding_engine.rb)
                    |
                    +-- module Trysac::RailsOnboardingEngine (lib/trysac/rails_onboarding_engine/)
                          +-- modules with pure module functions; no I/O, no global mutable state
                          +-- @api private helpers (optional)
```

- **Public API**: every public module, class, constant and method under `lib/` that is not marked
  `@api private`. Private helpers may change without a major version.
- **Errors**: invalid input raises an `ArgumentError` subclass of the library (such as
  `BlankInputError`) documented with `@raise`. The library never prints, exits, monkey-patches
  core classes or changes global state.
- **Side effects**: none. If a feature needs I/O, accept an IO object, a string or a small duck
  type instead of opening files, and record the choice in an ADR.

## Quality contract

`scripts/check.rb` is the single definition of the gates; `fabrica.json` tells the factory and CI
how to run it. See [TESTING.md](TESTING.md).

## Decisions

Architecture decisions are recorded in [decisions/](decisions/) as numbered ADRs.
