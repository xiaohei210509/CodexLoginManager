## Summary

Describe the problem and the outcome of this change.

## Changes

- Describe the main implementation change here.

## Verification

List the commands and manual checks you ran.

```text
swift test --disable-index-store -j 1
./script/build_and_run.sh --build
```

## Privacy and Security Impact

Describe any change to file access, authentication state inspection, CLI process
execution, redaction, persistence, macOS permissions, or network behavior. State
`None` only after considering each category.

## Screenshots

For visible UI changes, add manually sanitized screenshots. Remove account
details, usernames, home-directory paths, browser data, and login codes. Write
`Not applicable` when the change has no visible UI impact.

## Checklist

- [ ] The change is focused and does not include unrelated refactoring or generated artifacts.
- [ ] Tests pass with `swift test --disable-index-store -j 1`.
- [ ] The app bundle builds with `./script/build_and_run.sh --build`.
- [ ] I added or updated tests for behavior that can regress.
- [ ] I updated documentation and the `Unreleased` changelog when behavior changed.
- [ ] I reviewed the complete diff for secrets and private machine data.
- [ ] I did **not** include `auth.json`, API keys, OAuth tokens, JWTs, session cookies, or unredacted logs.
- [ ] Any screenshots and diagnostics were manually sanitized; I did not rely only on automated redaction.
- [ ] The app still delegates login and status checks to the official Codex CLI unless this change explicitly documents and justifies a new boundary.
- [ ] The app does not directly write `~/.codex/config.toml` unless this change explicitly documents and justifies that behavior.
- [ ] The change does not add a project-owned server, analytics, or telemetry without explicit prior discussion and documentation.

For a sensitive vulnerability, do not submit a public pull request before
coordinating through a private
[GitHub Security Advisory](https://github.com/xiaohei210509/CodexLoginManager/security/advisories/new).
