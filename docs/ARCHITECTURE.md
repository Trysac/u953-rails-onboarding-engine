# Architecture

## Overview

`Trysac::RailsOnboardingEngine` is a framework-free domain engine designed to be mounted by a web layer (such as a Rails Engine) while keeping all flow logic, validations, migrations, and cryptographic token handling pure and dependency-free.

## Components

1. **`Flow`, `Step`, and `Field`**:
   - Built via `Flow.define(name, version: 1) { ... }` and deeply frozen upon construction.
   - Each `Step` owns a map of `Field` definitions and an optional `if:` callable predicate.
   - `Field` validates and coerces `:string`, `:email`, `:integer`, `:boolean`, and `:enum` inputs, returning stable error code strings (`"required"`, `"too_long"`, `"invalid_email"`, `"not_an_integer"`, `"out_of_range"`, `"not_a_boolean"`, `"not_in_list"`).

2. **`Progress` and `Result`**:
   - `Progress` is an immutable value object containing `id`, `subject_id`, `flow_name`, `version`, `current_step`, `data`, `completed_steps`, `percent`, and per-step partitioned answers (`step_data`) so answers from steps whose `if:` condition turns false are cleanly dropped.
   - `Result` wraps step submission outcomes (`ok?`, `progress`, `errors`).

3. **`Engine`**:
   - Enforces input payload limits (at most 64 parameter keys and 10,000 characters per string value).
   - Orchestrates `start`, `submit`, `back`, `load`, `resume_token`, and `resume`.
   - Applies sequential `migrate(from: v)` blocks on `load` when stored progress has an older version, persisting the upgraded record once.
   - Emits privacy-safe events (`{type:, flow:, step:}`) without field values.

4. **`MemoryStore` and `JsonFileStore`**:
   - `MemoryStore` enforces a configurable `max_entries` cap (default 10,000), raising `:store_full` when exceeded.
   - `JsonFileStore` writes serialized JSON to a temporary file in the target directory and atomically renames it over the target file.

5. **`TokenCodec`**:
   - Encodes `{"f": flow_name, "p": progress_id, "v": version, "e": expiry_epoch}` as unpadded base64url followed by `.` and the unpadded base64url HMAC-SHA256 digest.
   - Verifies signatures with `OpenSSL.fixed_length_secure_compare` prior to JSON parsing.
