# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0-beta.4] - 2026-10-24

### Added

- Embed an adaptive native dictation patch engine and Acorn structural parser. Prepare
  official backups and locally signed patch copies from the installed client;
  no external script, Node.js, resource picker, or prebuilt Codex copy is needed.
- Keep backups in Application Support with process locking, transactional swaps,
  rollback, and interrupted-change recovery. Refuse unrecognized app hashes.
- Add isolated real-app round-trip coverage, alongside transaction safety tests.
- Generate independent per-build plans and backups; locate native integrity
  slots from Mach-O sections rather than hardcoded offsets.
- Show Update Codex only when the official stable feed offers an eligible update.
  Verify full ZIP length/Ed25519 and OpenAI signatures; download with progress and
  cancellation, request normal quit, transactionally install, and reopen.
- Reapply enabled compatible patches after updates, retaining the official new
  build with a warning if adaptation fails. Pin whole-bundle recovery identities.

### Fixed

- Use the fixed `plan_type=plus` update-query setting instead of `unknown`,
  while keeping `beta=false` and a manager-specific installation UUID.
  This does not detect or change an account subscription.
- Drain subprocess stdout and stderr concurrently to prevent pipe-buffer
  deadlocks during patch inspection and verbose tool execution.

### Distribution

- Include the patch engine, structural parser, rules, and third-party license
  in the universal macOS app. Official or modified Codex app copies are not
  distributed.
- Publish complete English and Simplified Chinese release notes from a
  version-controlled release-notes file.
- Keep the community prerelease ad-hoc signed and explicitly not Apple-notarized.

## [1.0.0-beta.3] - 2026-10-22

### Added

- Added a bilingual Dictation Patch tab alongside the existing login manager,
  with status refresh, version and backup information, a resource-folder picker,
  confirmed enable/disable actions, and interrupted-transaction recovery.
- Added a versioned JSON interface for a separately prepared local patch tool.
  The tool, official application backups, and patched application bundles are
  not included in the repository or downloadable app.
- Added coverage for patch status policy, protocol decoding, missing tool/runtime
  errors, CLI installation layouts, Finder launches, nvm version ordering, and
  sibling runtime discovery.

### Fixed

- Recognize the current bundled `codex-cli/bin/codex` wrapper and native
  `CodexCLI.app` executable while retaining the older bundled CLI layout.
- Discover system and user Applications folders, Homebrew, user-local, Volta,
  and nvm installations without relying on shell startup files.
- Rediscover the CLI when refreshing instead of retaining a stale path after
  an installation layout changes.
- Include the selected executable's directory in the restricted child-process
  `PATH`, allowing npm/nvm entrypoints to find their sibling Node runtime.

### Safety

- Keep login and patch mutation controls mutually disabled during operations.
  Patch switching is unavailable while Codex is running, for unsupported builds,
  or when required local resources are unavailable.
- Document the external tool protocol, trust boundary, local-signing effects,
  and the difference between source changes and published release assets.

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

[Unreleased]: https://github.com/xiaohei210509/CodexLoginManager/compare/v1.0.0-beta.4...HEAD
[1.0.0-beta.4]: https://github.com/xiaohei210509/CodexLoginManager/compare/v1.0.0-beta.3...v1.0.0-beta.4
[1.0.0-beta.3]: https://github.com/xiaohei210509/CodexLoginManager/compare/v1.0.0-beta.2...v1.0.0-beta.3
[1.0.0-beta.2]: https://github.com/xiaohei210509/CodexLoginManager/compare/v1.0.0-beta.1...v1.0.0-beta.2
[1.0.0-beta.1]: https://github.com/xiaohei210509/CodexLoginManager/releases/tag/v1.0.0-beta.1
