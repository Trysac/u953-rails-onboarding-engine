# Framework-free immutable flow engine with per-step answer partitioning and HMAC-SHA256 resume tokens

Status: accepted (generated, pending human review)

## Context

Multi-step onboarding wizards frequently branch based on earlier answers, evolve across deploys, and need safe resumption when users drop off. Coupling this state machine to Rails controllers or sessions makes branching progress calculations brittle and slow to test.

## Decision

Implement the flow definition (`Flow`, `Step`, `Field`) and state (`Progress`, `Result`) as frozen value objects driven by `Engine`. Partition collected answers by step inside `Progress` so re-evaluating step `if:` conditions on step submission immediately prunes data from branches that become invisible. Sign resume tokens with HMAC-SHA256 over unpadded base64url claims (`f`, `p`, `v`, `e`) and verify with constant-time comparison before JSON parsing.

## Consequences

Flows, branching percentages, version migrations, and token resumption can be tested deterministically in milliseconds with `MemoryStore` and `FrozenClock` using only the Ruby standard library, while a Rails host application can mount the engine and persist progress via any `#fetch`/`#save` store adapter.
