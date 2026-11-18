# Project record

## Objective

Multi-step onboarding flow engine with a declarative step DSL, conditional branches, progress percentages, versioned migrations and HMAC-signed resume tokens

## Scope

- In scope: the public API documented in [README.md](../README.md), documented and tested.
- Out of scope: anything that needs dependencies or I/O without an accepted ADR.

## Timeline

| Date | Event |
|---|---|
| 2026 | Repository created from the factory utility template. |

## Effort metrics

Measured values only; a value that has not been measured stays "pending measurement".

| Metric | Value |
|---|---|
| Tokens (input / output) | 2269586 / 31491 |
| Hours (human) | pending measurement |
| Cost (USD) | 1.0271 |

## Factory run u953 (measured from API usage)

| Date (UTC) | Phase | Model | Batch | Input | Output | Cache write | Cache read | Cost (USD) |
|---|---|---|---|---|---|---|---|---|
| 2026-11-17 | generation | google/gemini-4-argon | yes | 5786 | 24855 | 0 | 0 | 0.5202 |
| 2026-11-17 | fix-1 | google/gemini-3.8-flash | no | 94423 | 1391 | 0 | 431228 | 0.1084 |
| 2026-11-17 | fix-2 | google/gemini-3.8-flash | no | 86463 | 629 | 0 | 367567 | 0.0948 |
| 2026-11-17 | fix-3 | google/gemini-3.8-flash | no | 65224 | 603 | 0 | 188936 | 0.0654 |
| 2026-11-17 | fix-4 | google/gemini-3.8-flash | no | 128921 | 518 | 0 | 279034 | 0.1196 |
| 2026-11-18 | audit | google/gemini-3.8-flash | no | 93138 | 1359 | 0 | 523331 | 0.1142 |
| 2026-11-18 | docs | google/gemini-3.1-flash-lite | no | 5535 | 2136 | 0 | 0 | 0.0046 |

Total: $1.0271. Prices: vertex line, as measured by its adapter. Providers serve the current version of each model id, so the date tells which version answered; versions, launch stages and price sources per line are in the factory's model register (docs/MODELS.md).
