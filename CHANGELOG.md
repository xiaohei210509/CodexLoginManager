# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0-beta.2] - 2026-07-14

### Security

- Hardened named-secret redaction for quoted and escaped JSON fields, camelCase
  keys, authorization headers, bearer-token fields, OAuth client secrets, and
  opaque values wrapped across structurally bounded, indented lines.
- Hardened API-key and JWT redaction when token fragments are wrapped across
  adjacent indented lines. Ambiguous token-shaped continuation lines are now
  conservatively redacted, while blank lines, prose, structured diagnostics,
  and indentation rollbacks stop the scan.
- Redacted three-segment JWTs, including unsecured JWTs with an empty signature,
  and five-segment compact JWEs with the empty encrypted-key segment used by
  direct encryption.
- Rejected placeholder-like values and trailing secret text instead of trusting
  any value that merely starts with a redaction marker.
- Required a successful CLI exit and an exact positive status line before
  reporting ChatGPT login, so negated or failing output cannot spoof success.
- Stopped reflecting unrecognized `auth_mode` values from `auth.json` into the
  interface; unsupported modes now use fixed localized text.
- Preserved surrounding JSON fields and diagnostic structure instead of
  discarding internal indentation and blank lines during sanitization.

### Tests

- Added adversarial coverage for quoted and escaped JSON, authorization headers,
  compact JWE, multiline secrets, CRLF output, malformed token shapes,
  identifier-boundary false positives, and idempotence.
- Added service-level tests using temporary Codex CLI executables to verify that
  stdout and stderr are both scrubbed, unfamiliar CLI text remains visible,
  malformed `auth.json` contents are never echoed, and unrecognized
  `auth_mode` values cannot reach visible status fields.
- Added status-parsing coverage proving that negated text and nonzero exits do
  not report a successful ChatGPT login.

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

[Unreleased]: https://github.com/xiaohei210509/CodexLoginManager/compare/v1.0.0-beta.2...HEAD
[1.0.0-beta.2]: https://github.com/xiaohei210509/CodexLoginManager/compare/v1.0.0-beta.1...v1.0.0-beta.2
[1.0.0-beta.1]: https://github.com/xiaohei210509/CodexLoginManager/releases/tag/v1.0.0-beta.1
