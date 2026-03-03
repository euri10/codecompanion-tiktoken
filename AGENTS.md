<!-- br-agent-instructions-v1 -->

---

## Beads Workflow Integration

This project uses [beads_rust](https://github.com/Dicklesworthstone/beads_rust) (`br`/`bd`) for issue tracking. Issues are stored in `.beads/` and tracked in git.

### Essential Commands

```bash
# View ready issues (unblocked, not deferred)
br ready              # or: bd ready

# List and search
br list --status=open # All open issues
br show <id>          # Full issue details with dependencies
br search "keyword"   # Full-text search

# Create and update
br create --title="..." --description="..." --type=task --priority=2
br update <id> --status=in_progress
br close <id> --reason="Completed"
br close <id1> <id2>  # Close multiple issues at once

# Sync with git
br sync --flush-only  # Export DB to JSONL
br sync --status      # Check sync status
```

### Workflow Pattern

1. **Start**: Run `br ready` to find actionable work
2. **Claim**: Use `br update <id> --status=in_progress`
3. **Work**: Implement the task
4. **Complete**: Use `br close <id>` — the correct status keyword is **`closed`** (not `done`)
5. **Sync**: Always run `br sync --flush-only` at session end

### Key Concepts

- **Dependencies**: Issues can block other issues. `br ready` shows only unblocked work.
- **Priority**: P0=critical, P1=high, P2=medium, P3=low, P4=backlog (use numbers 0-4, not words)
- **Types**: task, bug, feature, epic, chore, docs, question
- **Blocking**: `br dep add <issue> <depends-on>` to add dependencies

### Commit Message Convention

- Always use Commitizen-style commit messages (e.g., `feat(module): short description`)

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
