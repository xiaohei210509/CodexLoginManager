# Contributing to CodexLoginManager

Thank you for helping improve CodexLoginManager. Contributions should keep the
application small, local-first, and transparent about its interaction with
Codex authentication state.

By participating, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Before You Start

- Search existing [issues](https://github.com/xiaohei210509/CodexLoginManager/issues)
  and pull requests before opening a duplicate.
- Use a GitHub Security Advisory, not a public issue, for a vulnerability that
  may expose credentials or private data. See [SECURITY.md](SECURITY.md).
- Open a feature request before investing in a large change or adding a new
  dependency.
- Keep changes focused. Unrelated refactors make authentication-related code
  harder to review.

## Privacy Is a Contribution Requirement

Never include real authentication material in an issue, pull request, commit,
test fixture, screenshot, or CI log. In particular, do not include:

- `~/.codex/auth.json` or excerpts from it.
- API keys, OAuth access/refresh/ID tokens, or JWTs.
- Unredacted logs or command output.
- Personal home-directory paths, account identifiers, or browser data.

Use clearly fake values and paths in tests and examples. Manually inspect all
diagnostics even if they have passed through `Redactor`; automated redaction is
defense in depth, not a guarantee.

## Development Requirements

- macOS 14 or later.
- Swift 6 / Xcode 16 or later.
- A Codex CLI supplied by ChatGPT.app, legacy Codex.app, or an executable
  `codex` on `PATH`.

Clone your fork and create a topic branch:

```bash
git clone https://github.com/YOUR-USER/CodexLoginManager.git
cd CodexLoginManager
git switch -c your-focused-branch
```

Build the application bundle without launching it:

```bash
./script/build_and_run.sh --build
```

Run the unit tests:

```bash
swift test --disable-index-store -j 1
```

The project build script uses an isolated SwiftPM scratch directory because the
default index store can stall in some macOS file-provider directories.

## Project Behavior to Preserve

Changes should accurately preserve or deliberately document these boundaries:

- The app reads local `~/.codex/auth.json` authentication metadata.
- The app delegates status checks and login to the official
  `codex login status` and `codex login` commands.
- The app does not directly write `~/.codex/config.toml`.
- The app has no project-owned server, analytics service, or telemetry endpoint.
- Sensitive CLI output is sanitized before display, but users are still warned
  to inspect logs manually.

Any proposal that changes one of these boundaries needs an explicit privacy and
security rationale in the pull request.

## Code and Test Guidelines

- Follow the existing Swift and SwiftUI structure and naming conventions.
- Prefer Foundation and platform APIs over adding a dependency for a small task.
- Keep filesystem and process behavior explicit and testable.
- Never make tests read a developer's real `~/.codex` directory.
- Use synthetic fixtures for authentication modes and redaction cases.
- Add focused tests for changes to credential detection, redaction, path
  resolution, or CLI process behavior.
- Keep comments concise and reserve them for non-obvious decisions.

## Documentation Changes

Update documentation when a change affects supported macOS versions, Codex CLI
discovery, authentication behavior, privacy boundaries, or troubleshooting.
Add user-visible changes to the `Unreleased` section of [CHANGELOG.md](CHANGELOG.md).

## Pull Requests

A pull request should contain:

- A clear explanation of the problem and the chosen approach.
- A focused diff without unrelated formatting or generated artifacts.
- Test results and manual verification appropriate to the change.
- Screenshots for visible UI changes, with all private data removed.
- A privacy and security impact assessment.

Before submitting, confirm:

- `swift test --disable-index-store -j 1` passes.
- `./script/build_and_run.sh --build` succeeds.
- No `.build/`, `dist/`, `tmp/`, credentials, or machine-specific files are
  staged.
- No `auth.json`, API key, OAuth token, JWT, or unredacted log appears anywhere
  in the diff.
- The pull request template is complete.

Maintainers may ask for a change to be split, simplified, or documented before
merging. Contributions are accepted under the repository's MIT License.
