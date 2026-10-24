# Embedded Adaptive Dictation Patch

The current source replaces beta.3's external Node.js script with native Swift
code, an embedded Acorn JavaScript parser, and structural detection. No external script, runtime,
resource-folder selection, or prebuilt app copy is required. This source
change is not yet in the published beta.3 release.

Compatibility is determined from the official artifact rather than a version
allowlist or minified filename. Acorn parses target JavaScript as data, without
executing it. Exactly one literal dictation declaration must have
`accessPolicy: "workspace-dictation"` and `requiresFirstPartyInference`.
Dynamic values, spreads, duplicates, ambiguous matches, and unfamiliar native
layouts fail closed. Mach-O sections locate each native integrity slot instead
of reusing offsets. Per-build generated plans pin the complete original/patched
ASAR hashes, header hashes, native slots, and original framework hash.
Only the provider declaration and its integrity metadata change.
Account/workspace checks and integrity-enable flags are not disabled.
Structural changes may still require a manager update. The old pinned recipe
is retained only for restoring legacy patches.

## Operations

- `status` is read-only. It reports installation and recovery readiness.
- `on` verifies the installed official signature, creates a local official
  backup, builds the patch from that copy, updates member/block/header/native
  integrity digests, signs helpers/framework/app in dependency order, verifies
  the staged artifact, and transactionally replaces the installed client.
- `off` restores the supported original application from a verified local backup.
- `recover` resolves an interrupted installation transaction.

Backups, generated copies, locks, and recovery journals live under
`~/Library/Application Support/CodexLoginManager/DictationPatch`.
Allow several GB of free space. No official or modified Codex bundle is
distributed or uploaded by the manager. Official updates are downloaded only
after user confirmation. The engine uses macOS system tools
(`ps`, `ditto`, `xattr`, `codesign`), Foundation/CryptoKit, and JavaScriptCore.
It never runs user-selected scripts.

Mutations hold a nonblocking OS file lock; a terminated process releases its
lock without trusting stale PID files. A candidate is staged on the installation
filesystem before renames. The previous installation is retained until final
verification; failures roll back or preserve the journal for recovery. A journal
also records the original target for recovery when the app is temporarily absent.
New transactions pin full content, file-permission, and symlink fingerprints
before and after replacement. Build-specific originals and patched copies live
under `builds/<build-and-original-hash>/`. Disabling after an upgrade restores
only that new build, never an older backup. Pre-update snapshots are retained
under `update-backups/`; the desired patch state is stored locally.

## Response Schema

The internal response retains the version-1 model introduced for beta.3,
including its strict decoder tests. It is no longer a subprocess JSON protocol.
The following is an illustrative status response:

```json
{
  "schemaVersion": 1,
  "ok": true,
  "status": {
    "state": "off",
    "installedApp": "/Applications/Codex.app",
    "installedVersion": "supported-build",
    "supportedVersion": "supported-build",
    "runningProcessCount": 0,
    "recoveryRequired": false,
    "officialBackupAvailable": true,
    "patchedArtifactAvailable": true,
    "installationWritable": true,
    "checkedAt": "2026-10-22T00:00:00Z"
  },
  "log": "",
  "error": null
}
```

`state` is one of:

- `on`: a supported installation with the prepared patch.
- `off`: a supported installation without the prepared patch.
- `notNeeded`: a verified official build whose provider flag is already disabled.
- `unknown`: the installation cannot be identified as a supported artifact.
- `missing`: the application is absent.

`installedVersion` may be null. Failures carry `ok: false` and an error message;
status is cleared if it cannot be refreshed. `officialBackupAvailable` and
`patchedArtifactAvailable` report local artifact presence, not a substitute for
the deep signature verification repeated before mutations.

## Safety Contract

The UI requires a supported state, no running Codex UI processes, no pending
recovery, and installation write access. A pristine supported client does not
need preexisting artifacts: first enable creates them automatically. Disabling
requires the local official backup but does not require a cached patch.
Recovery requires a pending transaction, a stopped Codex UI, and
write access, including when the application is temporarily missing.

These UI conditions are not a security boundary. The built-in engine repeats
checks before mutation, verifies supported artifact hashes and code signatures,
rechecks the installation after staging to detect updater changes, and preserves
a recoverable transaction journal. Normal patch switching does not terminate Codex
sessions or replace unsupported builds. It does not modify account/workspace authorization
checks, or overwrite user authentication/configuration files.

Enabling a locally signed client changes its signing identity and may affect
macOS permissions or team-bound integrations. Disabling must restore the
verified original backup. The manager cannot guarantee transcription service
availability. No recording or live transcription test is performed by this
interface. Unrecognized modifications are refused even when the version label
matches. An intact new official build is analyzed independently.

## Official Updates

The patch tab checks the stable official appcast on startup, refresh, activation,
and at 30-minute intervals while the view is active. The Update Codex button is
present only when an eligible newer build exists. Check failures hide the button
and display an error; they do not falsely report that the app is up to date.

Checks send version, CPU architecture, OS version, `beta=false`,
the fixed value `plan_type=plus`, and a manager-specific random UUID. This is an
update-query setting, not a detected account subscription. No Codex credentials
or installation identity are read. Only HTTPS requests to the official update
endpoint and expected `persistent.oaistatic.com/codex-app-prod/` feed/archive
paths are accepted, including redirects.

The XML parser rejects DTD/entities, ignores delta enclosures, validates
OS/architecture, and refuses version/build downgrades. Downloads have a size
cap; the full enclosure length and pinned official Sparkle Ed25519 signature
are verified **before extraction**. The app must also pass deep/strict OpenAI
signature, bundle ID, advertised version/build, and executable architecture checks.

After confirmation, download progress and cancellation are available until
installation begins. Only after verification does the manager request a normal
quit of the selected Codex app. It never force-quits: a failure to exit stops
installation. The full-app update does not depend on delta updates accepting a
locally patched app. Unrecognized local modifications can be replaced only in
this explicitly confirmed official update path, with an exact retained snapshot
and fingerprint-pinned rollback/recovery.

An enabled patch is analyzed and reapplied to the new official build. If it
cannot be safely adapted, the official update is kept with a warning. A pending
recovery journal prevents relaunch. Authentication/configuration files, projects,
and chat history are not edited. The manager does not intercept or disable the
official updater; updates performed elsewhere may overwrite a patch, and an
intact compatible official build can be patched again after refresh.

## Verification

Normal unit tests exercise AST matching, ASAR/block integrity, full-feed/delta
filtering, URL/version policies, signature failures, update-button policy,
missing resources, unknown builds, process locking,
transaction commit/rollback, invalid candidates, and missing-app recovery.
An opt-in real-artifact test copies a supplied official fixture into a temporary
directory, generates the patch, enables it, disables it, and checks restoration
of the official signature without touching `/Applications`:

```bash
CODEX_PATCH_OFFICIAL_FIXTURE=/path/to/official/ChatGPT.app swift test
```

Set `CODEX_UPDATE_OFFICIAL_ARCHIVE` to the pinned new official ZIP to additionally
test a real old-to-new isolated update, patch reapplication, and restoration of
the **new** official signature. Tests never update or terminate the running
main Codex application.
