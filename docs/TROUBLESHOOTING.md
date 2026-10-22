# Troubleshooting

This guide covers common installation, local build, and login-status problems.
The downloadable community beta requires macOS 14 or later. Building from
source additionally requires Swift 6 / Xcode 16 or later.

## Before Sharing Diagnostics

Never post `~/.codex/auth.json`, API keys, OAuth tokens, JWTs, session cookies,
or unredacted logs. Do not assume the built-in redactor found every private
value. Manually remove usernames, home-directory paths, account identifiers,
and browser data from text and screenshots.

**请勿上传 `auth.json`、API key、OAuth token、JWT 或未经人工脱敏的日志。**

## Confirm the Codex CLI Installation

Starting with v1.0.0-beta.3, the app checks each `ChatGPT.app` and `Codex.app` in
system and user Applications folders for these relative paths:

1. `Contents/Resources/codex-cli/bin/codex`
2. `Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex`
3. `Contents/Resources/codex` (older layouts)

It then checks `PATH`, common Homebrew directories, `~/.local/bin`, Volta,
and nvm installations. nvm versions are checked newest first using numeric
version ordering. Versions beta.1 and beta.2 use the older discovery logic;
update to beta.3 or newer if a current bundled CLI is not detected.

Check the app-bundled locations without printing authentication data:

```bash
test -x /Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex && echo "ChatGPT CLI found"
test -x /Applications/Codex.app/Contents/Resources/codex-cli/bin/codex && echo "Codex CLI found"
command -v codex
```

Print only the CLI version:

```bash
/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex --version
```

If the first path is absent, use the path reported by `command -v codex` or the
another supported bundled path. Do not create or download an unofficial executable to satisfy
the check.

## "Codex CLI Not Found"

- Confirm ChatGPT.app or Codex.app is installed in `/Applications` or your own
  `~/Applications`, not only in Downloads or another user's Applications folder.
- Common standalone installations are discovered even when Finder's `PATH`
  omits them; custom installations must expose `codex` on the app's `PATH`.
- Confirm the candidate is executable with `test -x PATH_TO_CODEX`.
- Click Refresh after changing the CLI installation. Rebuilding is not required.

The app deliberately does not search arbitrary directories or execute a path
provided by a remote service.

## "API Key Mode" Is Displayed

This means the local authentication mode is not confirmed as ChatGPT OAuth. It
is not necessarily a build error.

1. Run the official status command locally:

   ```bash
   codex login status
   ```

2. If you intend to use ChatGPT OAuth, use the application's login action or
   run the official login command:

   ```bash
   codex login
   ```

3. Complete the browser flow, return to the app, and refresh the status.

Do not manually paste tokens into `auth.json`. CodexLoginManager does not modify
`config.toml`; authentication configuration changes remain the responsibility
of the official Codex tools and the user.

## Login Opens but Never Completes

- Finish the browser authorization in the same macOS user session.
- Return to the terminal or app after the browser reports completion.
- Check whether `codex login status` completes outside the app.
- Verify that a firewall, proxy, VPN, or browser policy is not blocking the
  official login flow.
- Retry with the latest official Codex CLI available in ChatGPT.app or through
  the supported installation method you use.

The application waits for the official `codex login` process. It does not
receive passwords, device codes, or OAuth callbacks itself.

## `auth.json` Is Missing or Invalid

A missing file is expected before the first successful Codex login. If the file
exists but the app reports invalid JSON, validate its structure locally without
printing it:

```bash
plutil -lint ~/.codex/auth.json
```

Do not attach the file to an issue. Do not delete or rewrite it based solely on
an error message. Prefer re-running the official `codex login` flow, and make a
local backup before any manual recovery step.

## Build or Test Stalls

Use the repository's build script, which uses an isolated scratch directory and
disables the Swift index store:

```bash
./script/build_and_run.sh --build
```

For tests, use a temporary scratch path and one build job:

```bash
swift test \
  --scratch-path "${TMPDIR:-/tmp}/CodexLoginManager-tests" \
  --disable-index-store \
  -j 1
```

If a prior temporary build is corrupt, choose a new scratch-path name rather
than deleting unrelated SwiftPM or Xcode data.

## App Bundle or Code-Signing Verification Fails

Build a fresh app bundle with:

```bash
./script/build_and_run.sh --build
```

Then inspect the generated bundle:

```bash
xattr -cr dist/CodexLoginManager.app
plutil -lint dist/CodexLoginManager.app/Contents/Info.plist
codesign --verify --deep --strict dist/CodexLoginManager.app
```

The build script removes Finder/FileProvider extended metadata before applying
an ad-hoc signature. The signature is for local integrity checks; it is not an
Apple Developer ID signature or notarization.

Do not bypass Gatekeeper for a binary obtained from an untrusted source. Review
the source and build it locally.

## The Status Output Looks Sensitive

Close the app before sharing the screen. Treat any unexpected value as private.
The redactor covers known token patterns, but output can still contain paths,
account state, identifiers, or a credential format the project does not yet
recognize.

If the redactor missed a credential pattern:

1. Do not open a public issue containing the value.
2. Revoke or rotate the exposed credential if it was shared anywhere.
3. Report the pattern using a private
   [GitHub Security Advisory](https://github.com/xiaohei210509/CodexLoginManager/security/advisories/new)
   with a synthetic example.

## Opening a Support Issue

Use the repository's structured
[bug report form](https://github.com/xiaohei210509/CodexLoginManager/issues/new/choose)
and include:

- macOS version.
- Source revision or commit.
- Codex CLI version and installation method.
- Minimal reproduction steps.
- Expected and actual behavior.
- Sanitized diagnostics only when necessary.

For vulnerabilities or sensitive privacy failures, follow
[SECURITY.md](../SECURITY.md) and use a private Security Advisory instead.
