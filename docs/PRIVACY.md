# Privacy Guide

CodexLoginManager is a local macOS utility. It does not provide an account,
cloud backend, analytics service, advertising service, or project-owned
telemetry endpoint.

This document describes the behavior implemented by this repository. The
official Codex CLI, ChatGPT, OpenAI services, GitHub, and the user's browser are
separate products governed by their own terms and privacy policies.

## Data the Application Reads

CodexLoginManager reads the local `~/.codex/auth.json` file to determine:

- The `auth_mode` value.
- Whether `tokens.access_token` is present and non-empty.
- Whether the file is missing or cannot be parsed as JSON.

The application does not need to display the token value. The current status
summary reports only the authentication mode and whether an access token is
present.

The application also checks local filesystem paths to locate a Codex CLI in:

- `ChatGPT.app` and `Codex.app` in system or user Applications folders, including
  the current `Contents/Resources/codex-cli/bin/codex` wrapper, its native
  `CodexCLI.app` executable, and the older `Contents/Resources/codex` layout.
- An executable `codex` found on `PATH` or in common Homebrew, user-local,
  Volta, and nvm installation directories.

## Commands the Application Runs

CodexLoginManager delegates authentication operations to the official Codex
CLI:

- `codex login status` verifies the current login state.
- `codex login` starts the official browser-based login flow.

The CLI process runs with the current user's home directory and a restricted
executable search path: the selected executable's directory followed by standard
system and Homebrew directories. This lets nvm/npm entrypoints find their sibling
Node runtime without sourcing shell profiles. CodexLoginManager captures the
process output to show status and diagnostics in the interface.

The official CLI and browser flow may communicate with OpenAI services. Those
network requests are made by the official tools, not by a server operated by
this project.

## Data the Application Writes

The current source embeds a native Dictation Patch engine, replacing beta.3's
external script. Status reads application metadata, ASAR hashes,
backup presence, filesystem permissions, and process executable paths. It does
not read audio or account tokens for patch management.

Enable/disable/recovery may replace the installed Codex application using the
engine's local backup, staging, signature checks, transaction journal and rollback.
Enabling uses a locally signed client and may affect system permissions or
team-bound integrations. This is an explicit user action, not part of login
diagnostics. Patch logic, a JavaScript parser, and structural rules are embedded.
Official backups and patched app copies are generated locally under
`~/Library/Application Support/CodexLoginManager/DictationPatch`; they are
never bundled or uploaded. Preparation and signing invoke only
system tools (`ditto`, `xattr`, `codesign`); process checks use `ps`.

The patch tab also checks the official stable Codex update feed. HTTPS requests
send the installed app version, CPU architecture, OS version, `beta=false`,
the fixed value `plan_type=plus`, and a randomly generated manager-specific UUID
stored in local preferences. The plan parameter is a fixed update-query setting,
not a detected account subscription. No account token, project content, chat history, or Codex
installation identifier is read for update checking. Requests go only to
`updates.oaistatic.com` and the official `persistent.oaistatic.com` feed path.
These servers necessarily receive ordinary network metadata such as the IP
address. Checks run on refresh/activation and periodically while the view is active.

Only after explicit update confirmation does the manager download a full
official archive, verify its Ed25519 signature, and extract it in a temporary
directory. It requests a normal quit of the selected Codex app, retains a local
pre-update snapshot, transactionally installs the verified app, attempts to
reapply an enabled compatible patch, and reopens Codex. It never force-quits.
Downloads are cancellable before installation. The workflow uses several GB
of local disk space. No backup is sent to an external service.

The selected UI tab is persisted in local application preferences. The old
external resource preference is no longer used. Patch output is sanitized before display.

CodexLoginManager does not directly write `~/.codex/auth.json` or
`~/.codex/config.toml`. The official `codex login` command may update the Codex
authentication state as part of its normal login behavior.

The project does not implement a database, account store, analytics pipeline,
or upload service. Status and sanitized command output are held in application
state for the running process; the application does not implement its own
persistent log archive.

The local build script creates build artifacts under project or temporary build
directories. Those artifacts are excluded from version control.

## Redaction

Before CLI output is displayed, the application attempts to redact:

- Named `access_token`, `refresh_token`, `id_token`, and `api_key` values.
- `OPENAI_API_KEY` values.
- Common `sk-...` API key patterns.
- Common three-part JWT patterns beginning with `eyJ`.

Redaction reduces accidental exposure but is not a complete data-loss
prevention system. New credential formats, unusual formatting, account details,
paths, or other private data may not match the current rules.

## Sharing Diagnostics

Never upload or paste:

- `~/.codex/auth.json` or any excerpt from it.
- API keys, OAuth access/refresh/ID tokens, JWTs, or session cookies.
- Unredacted application or Codex CLI logs.
- Screenshots containing account details, private paths, browser data, or QR
  codes.

**Always inspect diagnostics manually, even when the application says they were
redacted. Replace private values with `<redacted>` before sharing.**

**请勿上传 `auth.json`、API key、OAuth token、JWT 或未经人工脱敏的日志。**

If a credential has already been shared, revoke or rotate it through the
appropriate official service. Editing or deleting a public post does not make
an exposed credential safe again.

## Permissions and Access

The source code does not request broad macOS permissions such as Contacts,
Photos, Camera, Microphone, or Location. It reads files and launches processes
with the permissions of the current macOS user.

Users can review the source and build locally. Downloadable community beta
archives are ad-hoc signed for integrity checks but do not claim Apple Developer
ID signing or notarization.

## Privacy Questions and Reports

- Report sensitive privacy or security problems through a private
  [GitHub Security Advisory](https://github.com/xiaohei210509/CodexLoginManager/security/advisories/new).
- Use [GitHub Issues](https://github.com/xiaohei210509/CodexLoginManager/issues/new/choose)
  for non-sensitive privacy questions and documentation corrections.

Do not include private data in either channel. A Security Advisory protects the
discussion from public disclosure, but the report should still use synthetic or
redacted examples whenever possible.
