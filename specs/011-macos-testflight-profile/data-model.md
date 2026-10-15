# Data Model: Portable macOS TestFlight signing

This feature adds no persisted product entity or migration. The records below model ephemeral release state and evidence so implementation, tests, and task dependencies use one vocabulary.

## ReleaseProfileRequest

Represents the existing lane's request to fetch or create the macOS App Store profile.

| Field | Constraint |
|---|---|
| app identifier | Existing VoxPocket app bundle identifier |
| team identifier | Existing paid Apple team |
| platform | `macos` |
| profile type | App Store distribution |
| force refresh | true, so current capabilities/certificates are represented |
| install | enabled for the current run |
| requested display name | absent; the lane does not prescribe a fixed name |

## CanonicalProfileName

Opaque profile display name published by Fastlane after successful acquisition and installation.

| Rule | Constraint |
|---|---|
| source | canonical `sigh_<app-id>_appstore_profile-name` output |
| validation | non-nil and non-blank before archive |
| confidentiality | never printed in failure messages or retained as evidence |
| transport | shell-escaped as one value |
| consumers | macOS archive setting and export provisioning map |

## ArchiveSigningHandoff

Target-specific in-memory boundary between Fastlane and XcodeGen-generated build settings.

| Field | Constraint |
|---|---|
| key | `VOXPOCKET_MAC_PROFILE_SPECIFIER` |
| value | validated `CanonicalProfileName` |
| target/SDK | VoxPocket app Release for `macosx` only |
| signing style | Manual |
| identity class | Apple Distribution |
| iOS impact | none; existing `iphoneos` profile setting remains unchanged |

## ExportSigningMapping

Export options for the macOS `.pkg`.

| Field | Constraint |
|---|---|
| app provisioning profile | same `CanonicalProfileName` used by `ArchiveSigningHandoff` |
| installer certificate selector | `Mac Installer Distribution` |
| team | existing team identifier |
| output | existing `.pkg` contract |

## ReleaseEvidence

Non-sensitive evidence allowed after the Owner-authorized production run.

| Field | Required | Exclusions |
|---|---|---|
| workflow run URL | yes | no raw authenticated URLs |
| exact `main` head SHA | yes | no unrelated branch state |
| build number | yes | no profile/certificate identifiers |
| terminal conclusion | yes | no secret/key/profile contents |
| distribution warnings | if present | no keychain output |

## State Transitions

```text
requested
  -> profile_fetched_and_installed
  -> canonical_name_validated
  -> archive_configured
  -> package_exported
  -> upload_processing_complete
  -> evidence_recorded
```

Failure transitions:

- profile acquisition failure -> stop before name resolution;
- missing/blank canonical name -> stop before archive;
- no valid existing Apple Distribution or Mac Installer Distribution identity -> fail without keychain mutation;
- unexpected artifact -> stop before upload;
- missing merge or Owner authorization -> production task remains blocked and undispatched.
