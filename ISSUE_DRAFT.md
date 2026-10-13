# DRAFT — upstream issue for expo/expo (Jon files this; do NOT file from automation)

> Copy the body below the line into a new issue at https://github.com/expo/expo/issues/new/choose
> (Bug report template). Attach the `evidence/` files when Jon's Play run completes.

---

## Summary

Android builds distributed as an AAB through Google Play embed a **stale** `expo-updates` `runtimeVersion` (`expo_runtime_version` in `strings.xml` / `AndroidManifest.xml` meta-data), so OTA updates are rejected with `updateRejectedBySelectionPolicy`. APK builds and iOS are correct. Follow-up to #41694 (closed for missing MRE).

## Link to the minimal reproducible example

https://github.com/D-Sports-Ecosystem/expo-updates-aab-runtime-repro

Stock Expo SDK 57 blank app + `expo-updates`, `expo-doctor` 21/21. Its single screen shows `Updates.runtimeVersion`, the JS-side config (`Constants.expoConfig`), and the binary version (`expo-application`), with a ✅/❌ verdict line. The repo includes `eas.json` (`apk` + `aab` profiles), a bump script, a no-Play local verification script, and APK/AAB inspectors.

## What happened

1. Built v1 (`runtimeVersion "1.0.0"`) — APK fine.
2. Bumped to v2 (`runtimeVersion "2.0.0"`, `versionCode` +1) and rebuilt **both** profiles.
3. Sideloaded v2 APK → app shows `Updates.runtimeVersion = 2.0.0` ✅
4. Installed v2 AAB from the Play internal track → app shows `Updates.runtimeVersion = 1.0.0` ❌ (stale)
5. Published an OTA update for runtime `2.0.0` → the Play build rejects it (`updateRejectedBySelectionPolicy`); the APK applies it.

<!-- Jon: attach evidence/ here -->
<!-- - evidence/apk-v2-correct.png -->
<!-- - evidence/play-aab-v2-stale.png -->
<!-- - evidence/play-ota-rejected.log -->
<!-- - evidence/inspect-aab-v2.txt (`bash scripts/inspect-aab.sh` output) -->

## What you expected to happen

`expo_runtime_version` baked into the AAB equals the config's `android.runtimeVersion` (`2.0.0`), identical to the APK build, and OTA updates for runtime `2.0.0` apply on Play installs.

## Steps to reproduce (exact)

```sh
git clone https://github.com/D-Sports-Ecosystem/expo-updates-aab-runtime-repro
cd expo-updates-aab-runtime-repro
npm install
bash scripts/configure-project.sh <your-eas-project-id>
bash scripts/repro-eas.sh --execute
# 1. eas build --platform android --profile apk        (v1)
# 2. bash scripts/bump-runtime.sh 2.0.0                (v1 -> v2)
# 3. eas build --platform android --profile apk        (v2, sideload: correct)
# 4. eas build --platform android --profile aab        (v2, Play internal track: stale)
```

Local (no EAS/Play) forensics included in the repo:

```sh
bash scripts/verify-local.sh   # prebuild + grep strings.xml/manifest across bump + dirty/clean prebuilds
bash scripts/inspect-apk.sh <v2.apk>
bash scripts/inspect-aab.sh <v2.aab>
```

## Environment

```
expo-env-info 2.1.0 environment info:
  System:
    OS: Linux 6.12 Ubuntu 24.04.5 LTS
    Shell: bash 5.2.21
  Binaries:
    Node: 22.14.0
    npm: 10.9.9
  npmPackages:
    expo: ~57.0.28 => 57.0.28
    expo-updates: ~57.0.26 => 57.0.26
    react: 19.2.3 => 19.2.3
    react-native: 0.86.3 => 0.86.3
```

- EAS CLI: <!-- Jon: `eas --version` output -->
- Device / Play track: <!-- Jon: device model + Android version + internal track -->
- `app.json` updates config: explicit string `runtimeVersion` top-level **and** `android.runtimeVersion`, `updates.url: https://u.expo.dev/<project-id>`, plugins `["expo-updates"]`, no `locales`.

## Platform(s)

Android (AAB via Google Play only). Android APK and iOS are unaffected.

## Did you reproduce in production?

Yes — release builds only (`apk` vs `aab` EAS profiles, `distribution` internal vs store, same `production` channel). Not Expo Go / dev-client specific.

## Workaround

Manually pin `expo_runtime_version` through `locales` JSON (only channel found to survive into Play AAB builds):

```json
// locales/en.json
{ "expo_runtime_version": "2.0.0" }
```

```json
{ "expo": { "locales": { "en": "./locales/en.json" } } }
```

Caution: a locale-qualified `expo_runtime_version` shadows the correct default for matching-locale devices, so the JSON must be bumped in lockstep with every release or it pins devices to a stale runtime.

## Additional context / suggested hypothesis

The config plugin writes the runtime as an indirect, locale-resolved string reference:

1. `withRuntimeVersionResource` writes `<string name="expo_runtime_version">` into default `values/strings.xml` — [`packages/@expo/config-plugins/src/android/Updates.ts`](https://github.com/expo/expo/blob/main/packages/@expo/config-plugins/src/android/Updates.ts) (`applyRuntimeVersionFromConfigAsync`).
2. `setVersionsConfigAsync` writes the manifest entry as a reference: `expo.modules.updates.EXPO_RUNTIME_VERSION = @string/expo_runtime_version` (same file).
3. `UpdatesConfiguration.getRuntimeVersion()` resolves it at runtime via `context.getMetadataValue(...)`, i.e. with the device's current locale — [`packages/expo-updates/android/src/main/java/expo/modules/updates/UpdatesConfiguration.kt`](https://github.com/expo/expo/blob/main/packages/expo-updates/android/src/main/java/expo/modules/updates/UpdatesConfiguration.kt).
4. Since SDK 54, `withLocales` writes per-language `values-b+<lang>/strings.xml` — [`packages/@expo/config-plugins/src/android/Locales.ts`](https://github.com/expo/expo/blob/main/packages/@expo/config-plugins/src/android/Locales.ts).

This MRE's local verification shows plain `expo prebuild` bakes the fresh value on clean **and** dirty prebuilds (`setStringItem` replaces in place — [`Strings.ts`](https://github.com/expo/expo/blob/main/packages/@expo/config-plugins/src/android/Strings.ts)), so the staleness likely enters downstream: EAS build-tools (note the *"ensure the same changes are also made in eas-cli and build-tools"* header in `Updates.ts`, with possibly divergent AAB/APK paths) or Play bundletool/split serving. The repo's `inspect-aab.sh` output discriminates the two: stale-in-AAB ⇒ build-time; fresh-in-AAB-but-stale-on-device ⇒ Play-time.

Prior report: #41694.
