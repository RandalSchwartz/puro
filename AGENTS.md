# Repository Guidelines: Puro Fork

Welcome to the fork of [Puro](https://github.com/RandalSchwartz/puro) maintained by Randal L. Schwartz (@RandalSchwartz).

## Architecture & Code Philosophy

Puro is a high-performance Flutter environment and version manager built in Dart. It achieves high speed and minimal disk usage through:
1. **Git Object Alternates (`objects/info/alternates`):** Multiple Flutter environments share a global Git object pool (`~/.puro/shared/flutter/.git/objects`).
2. **Shared Engine Caches:** Precompiled engine artifacts are downloaded once into `~/.puro/shared/caches/<engine-commit>` and symlinked to active environments.
3. **Shared Precompiled Tool Snapshots:** Flutter tool packages are precompiled to AOT/kernel snapshots in `shared/flutter_tools/<commit>/`.
4. **Non-Destructive IDE Integration:** VS Code settings (`.vscode/settings.json`) are updated via a custom AST parser and editor using `petitparser` (`lib/src/json_edit/`) to preserve developer comments and formatting.
5. **Strict Data Models:** Configuration, preferences, and JSON output structures are formalized with Protocol Buffers (`proto/puro.proto`).

## Core Invariants & Rules for AI Agents & Contributors

- **Preserve Non-Destructive Editing:** Never overwrite user configuration files (like IDE settings or project dotfiles) with naive string replaces or raw serialization. Use the AST-preserving editors.
- **Cross-Platform Robustness:** Always handle Windows, macOS, and Linux cleanly. Avoid brittle shell execution, unquoted paths, or regex stdout scraping when native Dart APIs or Win32 FFI can be used.
- **Concurrency & File Locks:** File writes and environment mutations must coordinate through `FileLock` (`lib/src/file_lock.dart`).
- **Atomic Operations:** Environment creation, upgrades, and downloads should stage into temporary locations and rename atomically to prevent half-provisioned environments upon interruption.
- **Testing:**
  - All bugfixes and new features must include automated tests in `puro/test/`.
  - Strive to increase test coverage around environment lifecycle and cache synchronization using mock or temporary file systems.
- **Code Hygiene:**
  - Code must pass `dart analyze --fatal-infos` with 0 warnings or infos.
  - Code must be formatted with `dart format`.
  - Public APIs must have clear Dart doc comments (`///`).

## Continuous Integration & Automated Review

- **CI Workflow:** `.github/workflows/ci.yml` validates formatting, static analysis, unit tests, and native AOT compilation.
- **GCA (Gemini Code Assist):** `.github/workflows/gemini-code-review.yml` provides automated architectural code reviews on PRs.
