---

## AI Agent Rules

AI-generated code must:

- Not introduce unsafe without invariants
- Not suppress lints
- Not introduce unwrap/expect
- Not add hidden panics
- Preserve API compatibility unless requested
- Keep abstractions minimal and composable
- Refactor instead of patching when possible
- Prefer safety and clarity over cleverness

Priority order:
1. Safety
2. Correctness
3. Clarity
4. Performance

---

## Rust Coding and Review Standards

- Never use `unwrap()`, `expect()`, `panic!()`, `todo!()`, or `unimplemented!()` in production code.
- Prefer explicit error types and use `thiserror` for error handling.
- Prefer borrowing over cloning; avoid unnecessary `.clone()`.
- Prefer traits and generic abstractions over concrete types.
- No hidden global mutable state; use `Arc`, `Mutex`, etc. as needed.
- Use a single async runtime consistently; never block inside async.
- All public items must be documented with Rust doc comments and examples.
- Unsafe code is forbidden by default (`#![forbid(unsafe_code)]`). If used, it must be encapsulated, documented, reviewed, and tested.
- Strict linting: `cargo clippy --all-targets --all-features -- -D warnings` must pass.
- All code must be formatted: `cargo fmt --all -- --check`.
- CI must fail on formatting, lint, test, or documentation errors.

## CodeCompanion Message Compatibility Notes

- Treat CodeCompanion chat message payloads as schema-flexible unless upstream types require a field.
- Verify optionality against upstream `codecompanion.nvim` definitions before tightening Rust deserializers.
- In upstream `lua/codecompanion/types.lua`, `CodeCompanion.Chat.ToolCall._index?` is optional, so Rust-side `ToolCall` parsing must tolerate missing `_index`.
- Tool lifecycle events such as `CodeCompanionToolsStarted` and `CodeCompanionToolsFinished` may surface message shapes where `tools.calls[*]._index` is absent.
- Other chat fields may also be omitted depending on call site or plugin version, including `_meta`, `opts`, `content`, `context`, and `tools` subfields.
- When changing message structs in `src/lib.rs`, prefer additive compatibility and add regression coverage for both present and absent optional fields.

---

## Session Checklist

```bash
git status              # Check what changed
git add <files>         # Stage code changes
br sync --flush-only    # Export beads changes to JSONL
git add .beads/         # Stage the JSONL export
git commit -m "..."     # Commit everything together
git push                # Push to remote
```

> **Always stage, commit, and push** after any code or beads changes — never leave the working tree dirty at session end.

After a successful `git push`, ask yourself: *"What did I learn or discover this session that is not yet captured in `AGENTS.md` or another doc?"* If anything is found, create a beads task immediately and update the docs.

---

<!-- end-br-agent-instructions -->
