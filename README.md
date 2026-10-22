<p align="center">
  <img src="Resources/AppIcon.png" width="128" height="128" alt="Codex Login Manager icon">
</p>

<h1 align="center">Codex Login Manager for macOS</h1>

<p align="center">
  Diagnose Codex CLI authentication and restart the official ChatGPT OAuth flow in one click.
</p>

<p align="center">
  <a href="README.zh-CN.md">简体中文</a>
  ·
  <a href="https://github.com/xiaohei210509/CodexLoginManager/releases"><strong>Download for macOS</strong></a>
</p>

<p align="center">
  <a href="https://github.com/xiaohei210509/CodexLoginManager/releases"><img src="https://img.shields.io/github/v/release/xiaohei210509/CodexLoginManager?include_prereleases&label=release" alt="Latest release"></a>
  <a href="https://github.com/xiaohei210509/CodexLoginManager/releases"><img src="https://img.shields.io/github/downloads/xiaohei210509/CodexLoginManager/total" alt="Downloads"></a>
  <a href="https://github.com/xiaohei210509/CodexLoginManager/actions/workflows/build.yml"><img src="https://github.com/xiaohei210509/CodexLoginManager/actions/workflows/build.yml/badge.svg" alt="Build"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple" alt="macOS 14+">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
</p>

![Codex Login Manager showing a confirmed ChatGPT OAuth login and the detected Codex CLI](docs/images/app-screenshot.png)

Codex Login Manager shows what the Codex CLI is actually using: ChatGPT OAuth, API-key mode, an incomplete `auth.json`, or a missing CLI. It then starts the official `codex login` flow and checks the result again. It does not implement OAuth itself, receive your password, or upload credentials.

## Why use this instead of only running `codex login`?

- See whether Codex is using ChatGPT OAuth or an API key.
- Find the CLI inside `ChatGPT.app` or `Codex.app`, on `PATH`, or in common standalone installation locations.
- Distinguish a missing, malformed, incomplete, or stale `~/.codex/auth.json`.
- Start the official browser login and automatically re-check when it finishes.
- Inspect command output with known API-key, OAuth-token, and JWT patterns redacted to reduce accidental exposure.
- Keep `~/.codex/config.toml` untouched.

## Install

1. Open the [Releases page](https://github.com/xiaohei210509/CodexLoginManager/releases).
2. Download `CodexLoginManager-*-macOS-universal.zip` and optionally verify it against `SHA256SUMS.txt`.
3. Unzip the app and move `CodexLoginManager.app` to `/Applications`.
4. Try to open the app once. If macOS blocks it, open **System Settings > Privacy & Security**, click **Open Anyway** for Codex Login Manager, then confirm **Open**.

The downloadable beta is universal for Apple Silicon and Intel Macs. It is open source and ad-hoc signed, but not Apple-notarized yet. macOS may therefore show an unidentified-developer warning. Follow [Apple's Open Anyway instructions](https://support.apple.com/en-us/102445); do not disable Gatekeeper globally.

Codex Login Manager requires macOS 14 or later and one of these official Codex CLI locations:

| Installation | CLI path |
| --- | --- |
| Current bundled CLI | `Contents/Resources/codex-cli/bin/codex` inside `ChatGPT.app` or `Codex.app` |
| Native bundled fallback | `Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex` |
| Older app layout | `Contents/Resources/codex` |
| Standalone CLI | `PATH`, Homebrew, `~/.local/bin`, Volta, or nvm installations |

The local development build checks system and user Applications folders and
rediscovers the CLI on refresh. Finder launches do not require shell startup
files to expose nvm. These discovery changes are not a new published release.

## Local dictation patch management

The local development build adds a Dictation Patch tab for status, supported build,
backup readiness, enable/disable, and interrupted-transaction recovery. It calls the
prepared local `codex-dictation-research/dictation-patch.mjs` tool; the resource folder
can be changed in the UI. Official application bundles are not included in this repository.
The local tool is not bundled; see the [tool protocol and trust requirements](docs/DICTATION_PATCH_PROTOCOL.md).

Enabling replaces the installed Codex with a locally signed build. Permissions or
sign-in may be requested again, and some system integrations may be unavailable.
Disabling restores the official backup. Account/workspace checks remain intact, and
real transcription still requires manual verification. This is a local development
feature, not a new public release.

## Privacy and security

- Reads `~/.codex/auth.json` locally to identify the authentication mode.
- Runs the installed official `codex login status` and `codex login` commands.
- Redacts named secrets, OpenAI-style API keys, and JWTs before displaying CLI output.
- Does not write to `~/.codex/config.toml`.
- Has no analytics, account system, project server, or third-party network request of its own.

Do not attach `auth.json`, API keys, OAuth tokens, JWTs, or unredacted logs to a public issue. See [Privacy](docs/PRIVACY.md) and [Security](SECURITY.md) for the exact trust boundary.

## Build from source

Requirements: macOS 14+, Swift 6, and Xcode 16 or newer.

```bash
git clone https://github.com/xiaohei210509/CodexLoginManager.git
cd CodexLoginManager
./script/build_and_run.sh
```

Other useful commands:

```bash
swift test --disable-index-store -j 1
./script/build_and_run.sh --build
./script/build_and_run.sh --verify
./script/package_release.sh 1.0.0-beta.2
```

The app follows the macOS language setting and currently includes English and Simplified Chinese. GitHub Actions runs unit tests, builds the app bundle, verifies its signature, and packages tagged universal releases.

## Help and contributing

- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Privacy details](docs/PRIVACY.md)
- [Security policy](SECURITY.md)
- [Contributing guide](CONTRIBUTING.md)
- [Changelog](CHANGELOG.md)

Bug reports and focused pull requests are welcome. Please follow the issue templates so logs and authentication data stay safely redacted.

## License and trademark notice

Codex Login Manager is available under the [MIT License](LICENSE). It is an independent community project, not an official OpenAI product and not affiliated with or endorsed by OpenAI. ChatGPT, Codex, and OpenAI are trademarks of their respective owners.
