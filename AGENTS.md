# Repository Guidelines

## Project Structure & Module Organization
This repository is part of the Ziggy* codebase and is a Zig package.

- `src/` contains package source files.
- `build.zig` defines build targets.
- `build.zig.zon` contains package metadata.
- `README.md` documents package purpose and usage.

## Build, Test, and Development Commands
- `zig build` - build configured artifacts.
- `zig build test` - run package tests.
- `zig fmt src/*.zig` - format source files.
- If source changes, run `zig build` and `zig build test` before pushing.

## Coding Style & Naming Conventions
- Follow Zig style and keep code `zig fmt` clean.
- Use `snake_case` for functions/variables/constants where possible.
- Use `PascalCase` for public types.
- Prefer explicit error handling with `try`/`catch` and early returns.

## Testing Guidelines
- Add tests close to changed behavior.
- Prefer focused tests with deterministic inputs.
- Run `zig build test` before opening or updating a PR.

## Commit & Pull Request Guidelines
- Use clear imperative commit messages.
- PR descriptions should include:
  - Summary of purpose and impact.
  - Commands run (`zig build`, `zig build test`).

## Branch Protection And Review Gate
- Direct pushes to `main` are not allowed.
- All changes that update `main` must go through a pull request.
- A PR must not be merged until `chatgpt-codex-connector` (including variants like `chatgpt-codex-connector[bot]`) has reviewed it.
- Do not merge while any review comments from that reviewer remain outstanding.
- Every Codex review conversation thread must be explicitly resolved in GitHub before merge.
- Replying is not enough: resolve the thread after addressing it.
- After each Codex pass, immediately check for new open Codex threads and repeat: fix -> reply -> resolve -> `@codex review`.
- Do not merge until there are zero open Codex review threads and no outstanding Codex comments.
- The first Codex review cycle is automatic when a PR is opened.
- After each additional change cycle (any push after Codex feedback), the PR author must comment `@codex review` to request a fresh Codex pass.
- Merge requires a Codex response that is newer than both the latest `@codex review` request and the PR head commit.
- Escape clause: if Codex is stalled (latest Codex response older than 10 minutes) or review threads cannot be cleared due tooling/infrastructure issues, auto-merge must remain disabled; a maintainer may merge manually only after posting an explicit override rationale on the PR.

## Compatibility Policy
- Until `1.0.0`, backward compatibility is not guaranteed.
- Breaking changes are allowed during early development, but should be documented in PR notes.
