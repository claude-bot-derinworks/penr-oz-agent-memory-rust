# AGENTS.md — Contributor Guide for AI Agents

This file provides structured guidance for AI coding agents working on this repository.

---

## Project Purpose and Architecture

**penr-oz-agent-memory-rust** is an HTTP server that acts as a vector-memory store proxy for AI agents. It:

- Accepts natural-language text, generates embeddings via a pluggable provider (Ollama, OpenAI, Anthropic/Voyage AI), and stores them for semantic retrieval.
- Exposes two storage backends: an **in-memory store** (fast, ephemeral) and an optional **Qdrant vector database** (persistent).
- Optionally tracks **sessions** in SQLite, with API-key authentication on session endpoints.

### Module map

| Path | Responsibility |
|------|---------------|
| `src/main.rs` | Startup, router wiring, shared state (`AppState`) construction |
| `src/config.rs` | `Config` struct deserialised from `config.toml` |
| `src/routes.rs` | Axum handlers, request/response types, auth helper |
| `src/memory.rs` | In-memory vector store (`MemoryStore`) |
| `src/vector_store.rs` | Qdrant client wrapper (`QdrantStore`) |
| `src/session_store.rs` | SQLite session store (`SessionStore`) |
| `src/embedding/mod.rs` | `EmbeddingProvider` trait, `ProviderRegistry` |
| `src/embedding/ollama.rs` | Ollama provider |
| `src/embedding/openai.rs` | OpenAI-compatible provider (also used for Azure) |
| `src/embedding/claude.rs` | Anthropic/Voyage AI provider |
| `src/error.rs` | Error enums that implement `IntoResponse` |
| `examples/agent_client.rs` | Self-contained demo client |

---

## Build and Test Commands

All commands are run from the repository root.

```sh
# Check that the project compiles (no external services needed)
cargo check

# Run all tests
cargo test

# Run the server (requires config.toml and, for Qdrant, a running Qdrant instance)
cargo run

# Run the example client (requires a running server)
cargo run --example agent_client
```

There is no separate lint step; `cargo check` and `cargo test` are sufficient for CI validation.

---

## Coding Conventions

- **Edition**: Rust 2021. Match the style of surrounding code.
- **Formatting**: Standard `rustfmt` defaults. Run `cargo fmt` before committing if you edit `.rs` files.
- **Error handling**: Use the typed error enums in `src/error.rs` (`EmbeddingError`, `VectorStoreError`, `SessionError`). Each implements `IntoResponse` so handlers can return `Result<_, ErrorType>` directly. Do not introduce `anyhow` or `Box<dyn Error>` in handler code.
- **Comments**: Write comments only when the *why* is non-obvious. Do not add docstrings that restate what the function name already says. Existing handlers have short doc comments that describe request semantics; follow that pattern when adding new handlers.
- **No `unwrap` in handler code**: Use `?` propagation or map errors to the appropriate typed error.
- **Logging**: Use `tracing::{info, warn, error}` with structured key-value fields, e.g. `info!(memory_id = %id, "Memory entry deleted")`.
- **Async**: All I/O is async via `tokio`. Do not spawn blocking tasks for anything already supported by `reqwest` or `sqlx`.

---

## API Modification Rules

1. **Request/response types live in `src/routes.rs`** alongside their handler. Add new types next to the relevant handler section.
2. **All new routes must be registered** in `main.rs` via the `Router::new()` chain.
3. **Reserved metadata keys**: `"text"` and `"session_id"` are reserved in the Qdrant payload (`RESERVED_TEXT_KEY_ERROR`, `RESERVED_SESSION_ID_KEY_ERROR` in `src/vector_store.rs`). Do not remove or rename these checks.
4. **Provider selection**: Handlers that call into an embedding provider must honour the `?provider=<name>` query parameter by calling `registry.get(Some(provider_key))`. Never hard-code a provider name in a handler.
5. **Optional features stay optional**: Qdrant and the session store are behind `Option<Arc<_>>` in `AppState`. Handlers that require them must return the appropriate "not configured" error (e.g. `VectorStoreError::NotConfigured`, `SessionError::NotConfigured`) rather than panicking.
6. **Auth**: Any new endpoint that operates on session data must call `validate_session_auth` the same way existing session handlers do.
7. **Backward-compatible defaults**: If you add a new field to a request struct, give it a `#[serde(default)]` annotation so existing callers are not broken.

---

## File Organisation

- **One module per concern**: keep embedding providers in `src/embedding/`, add new providers there as `src/embedding/<name>.rs` and register them in `src/embedding/mod.rs`.
- **Examples go in `examples/`** with a single `.rs` file per example.
- **Config changes** require a matching entry in `config.toml` (commented out by default if the feature is optional) and a corresponding field in `src/config.rs`.
- Do not create new top-level source files without a matching `mod` declaration in `main.rs`.

---

## Documentation Expectations

- Update `README.md` when you add or change an API endpoint, a configuration key, or an embedding provider.
- The API table in `README.md` must stay in sync with the routes registered in `main.rs`.
- Do not create additional Markdown files (planning docs, analysis notes, etc.) — use commit messages and PR descriptions instead.

---

## Commit Message Conventions

Use the imperative mood and keep the subject line under 72 characters.

```
Add session filtering to /api/search endpoint

Extend the Qdrant search handler to accept an optional `session_id`
query parameter and filter results to that session.
```

Prefix with a category when it helps readers scan history:

| Prefix | When to use |
|--------|-------------|
| `feat:` | New capability visible to API callers |
| `fix:` | Bug fix |
| `refactor:` | Internal restructuring with no behaviour change |
| `test:` | Adding or updating tests only |
| `docs:` | Documentation-only changes |
| `chore:` | Dependency bumps, CI changes, config tweaks |

---

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `CONFIG_PATH` | `config.toml` | Path to the TOML configuration file |
| `RUST_LOG` | `info` | Log level filter (e.g. `debug`, `warn`) |
| `SESSION_API_KEY` | _(unset)_ | When set, all `/api/sessions` endpoints require `X-Api-Key: <value>` |

---

## Running External Dependencies Locally

The fastest path is Docker Compose (see `README.md`). When writing or running tests:

- Tests that exercise the embedding providers use `wiremock` to mock HTTP — no live provider is needed.
- Tests that exercise SQLite use an in-memory database (`sqlite::memory:`) — no file is created.
- No test should require a live Qdrant instance or a real embedding API key.
