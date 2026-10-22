# Local Dictation Patch Tool

The Dictation Patch tab is a frontend for a separately prepared, trusted local
tool. This repository does not ship that tool, official Codex application
backups, patched application bundles, or a service that supplies them. A missing
tool is reported in the patch tab and does not prevent login diagnostics.

Select the resource folder with the folder button in the patch tab. It must
contain `dictation-patch.mjs` and any resources that tool requires. Selecting a
folder immediately invokes its status command; only select scripts you trust.
The selected folder is stored in local application preferences.

## Invocation

The application locates a local Node executable and runs:

```text
node /path/to/resources/dictation-patch.mjs --json status
node /path/to/resources/dictation-patch.mjs --json on
node /path/to/resources/dictation-patch.mjs --json off
node /path/to/resources/dictation-patch.mjs --json recover
```

- `status` must be read-only. It reports installation and recovery readiness.
- `on` enables the prepared patch for an explicitly supported installation.
- `off` restores the supported original application from a verified local backup.
- `recover` resolves an interrupted installation transaction.

The working directory is the user's home, so the tool must resolve resources
relative to its own script location rather than the working directory. Status
has a 45-second timeout. Mutation commands have no application-imposed timeout,
to avoid terminating a filesystem transaction midway.

## Response Schema

Write one JSON envelope to stdout, not human-readable progress followed by JSON.
Put diagnostic text in `log`, and never include credentials or audio contents.
The following is an illustrative status response; version strings must describe
the actual local installation and supported artifact:

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
- `unknown`: the installation cannot be identified as a supported artifact.
- `missing`: the application is absent.

`installedVersion` may be null. On failure, exit nonzero, set `ok` to false,
and provide `error` as an object with a `message` string. Return the latest safe
status when possible, or null when it cannot be determined. Keep `log` a string.
The UI rejects unrecognized schema versions and invalid state values.

## Safety Contract

The UI requires a supported state, no running Codex UI processes, no pending
recovery, both prepared artifacts, and installation write access before enabling
the switch. Recovery requires a pending transaction, a stopped Codex UI, and
write access, including when the application is temporarily missing.

These UI conditions are not a security boundary. The external tool must repeat
all checks immediately before mutation, verify supported artifact hashes and
code signatures, handle concurrent updater changes, stage replacements safely,
and preserve a recoverable transaction journal. It must not terminate Codex
sessions, replace unsupported builds, modify account/workspace authorization
checks, or overwrite user authentication/configuration files.

Enabling a locally signed client changes its signing identity and may affect
macOS permissions or team-bound integrations. Disabling must restore the
verified original backup. The manager cannot guarantee transcription service
availability or the safety of an arbitrary user-selected script. No recording
or live transcription test is performed by this interface.
