# Contract: macOS current-run signing handoff

## Purpose

Bind the profile acquired in the current authorized macOS TestFlight run to both archive and export without a fixed profile display name, new credential, or keychain mutation.

## Producer: Fastlane mac lane

The mac lane MUST:

1. authenticate through the existing App Store Connect API-key contract;
2. acquire and install the VoxPocket app's App Store profile for `platform: "macos"` with `force: true` and no `provisioning_name`;
3. read the canonical display name from `lane_context[SharedValues::SIGH_NAME]`, as published by Fastlane 2.241.0's real `GetProvisioningProfileAction`;
4. reject nil or blank output before `build_app` without interpolating the value into logs/errors;
5. shell-escape the opaque value and bind it to `VOXPOCKET_MAC_PROFILE_SPECIFIER` in archive arguments;
6. reuse the exact validated variable for `export_options.provisioningProfiles[APP_IDENTIFIER]`;
7. use `Mac Installer Distribution` as the installer certificate automatic selector.

The producer MUST NOT:

- pass the fixed name `VoxPocket Mac App Store` as `provisioning_name`;
- read `ENV["sigh_#{APP_IDENTIFIER}_appstore_profile-name"]` or another fabricated per-app environment key;
- use the provisioning action return, which is the profile UUID, as a display-name fallback source;
- add a global `PROVISIONING_PROFILE_SPECIFIER` archive override;
- log provisioning-profile contents, certificate contents or identifiers, private-key material, App Store Connect API-key material, keychain passwords, or other secret material (a provisioning-profile display name may appear in authorized release logs);
- import, replace, unlock differently, or otherwise mutate keychain/certificate state beyond the existing workflow preparation;
- change iOS lane behavior.

## Consumer: XcodeGen macOS Release setting

`VoxPocket/project.yml` MUST retain:

- base/Debug `CODE_SIGN_STYLE: Automatic`;
- app Release `CODE_SIGN_STYLE: Manual`;
- app Release `CODE_SIGN_IDENTITY: Apple Distribution`;
- existing iPhoneOS profile configuration.

Its `PROVISIONING_PROFILE_SPECIFIER[sdk=macosx*]` MUST consume `$(VOXPOCKET_MAC_PROFILE_SPECIFIER)` and MUST NOT contain a fixed display name.

The current `VoxPocket/VoxPocket.xcodeproj/project.pbxproj` MUST remain synchronized from that source, and neither project file may be edited by this repair.

## Workflow invariants

The executable `.github/workflows/testflight.yml` contract remains:

- trigger: explicit `workflow_dispatch` only;
- checked-out ref: `main`;
- authorized platform: macOS only;
- active upload cancellation: disabled;
- no-new-commit skip retained unless `force=true`;
- existing secret names unchanged;
- existing login-keychain unlock/access step unchanged;
- packaging regression runs before credentials are used for the lane;
- successful lane completion precedes release-tag movement.

No workflow executable line or comment may change in this repair.

## Regression contract

Credential-free tests MUST prove:

- the historical fixed-name configuration fails;
- the mac profile request is forced, installed, macOS-specific, and has no requested display name;
- the real `GetProvisioningProfileAction` class publishes the fixture display name through `SharedValues::SIGH_NAME` in actual lane context while returning a distinct fixture UUID;
- the fixture stubs only `Sigh::Manager.start` at the external acquisition boundary, clears/restores lane context, and does not stub the action or fabricate its return as the name;
- missing/blank `SharedValues::SIGH_NAME` fails before build;
- opaque values with whitespace/metacharacters survive as one archive assignment;
- archive and export reuse the same value;
- the macOS XcodeGen setting consumes only the custom macOS key;
- installer export uses the generic selector and contains no personal subject;
- manual/macOS-only/build-number/package/upload/tag invariants remain intact;
- no test signs, uploads, moves a tag, unlocks a keychain, or calls App Store Connect.

## Production evidence contract

After reviewed merge and explicit Owner authorization, record:

- consent reference;
- workflow run URL;
- exact merged `main` SHA used by the run;
- build number;
- terminal conclusion and non-sensitive distribution warnings.

Never copy into the evidence record App Store Connect API-key material, `.p8` data, signing private-key material, provisioning-profile contents, certificate contents/subject/hash, keychain output/passwords, or local credential paths; a provisioning-profile display name appearing in the authorized release log is permitted.
