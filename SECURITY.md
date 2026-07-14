# Security Policy

CodexLoginManager handles authentication metadata on the local Mac, so reports
about credential exposure, unsafe command execution, or misleading login state
are treated as security-sensitive.

## Supported Versions

Security fixes target the latest revision on the default branch and the latest
tagged beta or stable release. Older snapshots may receive fixes only when the
change can be applied safely.

| Version | Supported |
| --- | --- |
| Latest default branch | Yes |
| Latest tagged release | Yes |
| Older snapshots | Best effort |

## Reporting a Vulnerability

Do not open a public issue for a vulnerability that could expose credentials or
private data. Submit a private report through the repository's
[GitHub Security Advisories](https://github.com/xiaohei210509/CodexLoginManager/security/advisories/new)
page instead.

For non-sensitive security hardening suggestions, open a
[GitHub Issue](https://github.com/xiaohei210509/CodexLoginManager/issues/new/choose).
If you are uncertain whether a report is sensitive, use a Security Advisory.

Include only the minimum information needed to reproduce the problem:

- The affected commit, tag, or source revision.
- The macOS and Codex CLI versions.
- The Codex CLI installation path or installation method.
- Reproduction steps using dummy credentials and sanitized paths.
- The security impact and any known workaround.

The maintainer will review the report, request clarification if needed, and
coordinate disclosure through the advisory. No response-time or release-time
guarantee is currently offered.

## Never Include Secrets

Never upload, paste, attach, or commit any of the following:

- `~/.codex/auth.json`, in whole or in part.
- API keys, including values beginning with `sk-`.
- OAuth access, refresh, or ID tokens.
- JWTs or session cookies.
- Unredacted Codex CLI output, application logs, screenshots, or crash reports.
- Private usernames, home-directory paths, account identifiers, or browser data.

**Security warning: do not rely on the application's redactor as a guarantee.**
Review every report manually and replace sensitive values with obvious dummy
text such as `<redacted>`.

**安全警告：请勿上传 `auth.json`、API key、OAuth token、JWT 或未经人工检查的日志。**

If a secret was exposed, revoke or rotate it through the appropriate official
service before continuing the report. Removing a secret from a comment does not
invalidate a credential that has already been disclosed.

## Security Boundaries

CodexLoginManager:

- Reads the local `~/.codex/auth.json` file to determine the authentication
  mode and whether an access token is present.
- Calls the official `codex login status` command to verify login state.
- Calls the official `codex login` command to start the browser-based login
  flow.
- Sanitizes known API key and token patterns before showing CLI output.
- Does not directly write `~/.codex/config.toml`.
- Does not operate a project-owned server, analytics service, or telemetry
  endpoint.

The official Codex CLI and browser-based authentication flow are separate
components with their own security and privacy behavior. A vulnerability in
those components should also be reported through the relevant official channel.

## Disclosure Expectations

Please allow time for investigation and remediation before publishing details.
Do not test against accounts, devices, or credentials that you do not own or
have explicit permission to use.
