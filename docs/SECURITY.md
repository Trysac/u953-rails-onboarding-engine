# Security & Threat Model

## Threat Model

1. **Token Tampering and Forgery**:
   - Resume tokens are signed with HMAC-SHA256 (RFC 2104) using a secret that must be at least 32 bytes (`Error` with `:invalid_flow` otherwise).
   - `TokenCodec` verifies the signature over the raw base64url payload using `OpenSSL.fixed_length_secure_compare` before decoding or parsing any JSON.
   - Tokens bind the flow name (`"f"`), progress ID (`"p"`), flow version (`"v"`), and expiration timestamp (`"e"`). Tokens issued for one flow cannot be used on another.

2. **Information Disclosure in Tokens, Logs, and Errors**:
   - Resume tokens never carry user-submitted field values.
   - `on_event` callbacks receive only `{type:, flow:, step:}` metadata, never user answers.
   - `Error` truncates any message to at most 200 characters.

3. **Denial of Service & Resource Exhaustion**:
   - `Engine#submit` rejects parameter hashes with more than 64 keys or string values exceeding 10,000 characters (`:payload_too_large`).
   - `MemoryStore` caps capacity at `max_entries` (default 10,000) and raises `:store_full` on overflow.
   - `JsonFileStore` restricts progress IDs to `/\A[a-zA-Z0-9_-]{1,128}\z/` to prevent path traversal.
