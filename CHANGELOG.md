# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0-beta.1] - 2026-07-14

### Added

- Native macOS SwiftUI interface for diagnosing Codex CLI authentication.
- Codex CLI discovery in ChatGPT.app, legacy Codex.app, and `PATH`.
- Local inspection of `~/.codex/auth.json` without displaying token values.
- Login verification and browser authorization through the official
  `codex login status` and `codex login` commands.
- Redaction of known API key, OAuth token, and JWT patterns before CLI output
  is shown.
- English and Simplified Chinese interface localization.
- Privacy-safe path display that abbreviates the current home directory as `~`.
- Universal Apple Silicon and Intel release packaging with SHA-256 checksums.
- Security, privacy, troubleshooting, contribution, issue, and pull request
  documentation.

### Security and Privacy

- The application does not directly write `~/.codex/config.toml`.
- The project does not operate a server, analytics service, or telemetry
  endpoint.
- Downloadable beta archives are ad-hoc signed and explicitly identified as not
  Apple-notarized.

[Unreleased]: https://github.com/xiaohei210509/CodexLoginManager/compare/v1.0.0-beta.1...HEAD
[1.0.0-beta.1]: https://github.com/xiaohei210509/CodexLoginManager/releases/tag/v1.0.0-beta.1
