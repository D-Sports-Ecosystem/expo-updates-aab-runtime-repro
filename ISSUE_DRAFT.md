# DRAFT — upstream issue for expo/expo (Jon files this; do NOT file from automation)

> Copy the body below the line into a new issue at https://github.com/expo/expo/issues/new/choose
> (Bug report template). Attach the `evidence/` files when Jon's Play run completes.

---

## Summary

Android builds distributed as an AAB through Google Play embed a **stale** `expo-updates` `runtimeVersion` (`expo_runtime_version` in `strings.xml` / `AndroidManifest.xml` meta-data), so OTA updates are rejected with `updateRejectedBySelectionPolicy`. APK builds and iOS are correct. Follow-up to #41694 (closed for missing MRE); same mechanism as #48148 (open, with device-level proof of Play-side injection).

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
<!-- - evidence/play-aab-v2-english.png (locale-switch test) -->
<!-- - evidence/play-translation-setting.png (Play Console translation setting) -->
<!-- - evidence/device-splits.txt (`bash scripts/pull-device-splits.sh` output) -->
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
bash scripts/pull-device-splits.sh  # adb: base.apk vs split_config.*.apk per-locale grep
```

Play-side checks: note Play Console → Grow users → Translations → App strings (automatic app-string translation on/off), and repeat the on-device read after switching device language to English + reinstalling — if the stale value flips to correct, a Play-injected locale-qualified split is overriding the default (#48148 signature).

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
- Play Console → Grow users → Translations → App strings: <!-- Jon: automatic translation on/off? -->
- `app.json` updates config: explicit string `runtimeVersion` top-level **and** `android.runtimeVersion`, `updates.url: https://u.expo.dev/<project-id>`, plugins `["expo-updates"]`, no `locales`.

## Platform(s)

Android (AAB via Google Play only). Android APK and iOS are unaffected.

## Did you reproduce in production?

Yes — release builds only (`apk` vs `aab` EAS profiles, `distribution` internal vs store, same `production` channel). Not Expo Go / dev-client specific.

## Workarounds

1. Disable app-string translation in Play Console (confirmed fix in #48148), then upload a **new** bundle — already-published bundles keep their injected translations.
2. Manually pin `expo_runtime_version` through `locales` JSON (forces a locale-qualified value into the bundle that overwrites the translated one):

```json
// locales/en.json
{ "expo_runtime_version": "2.0.0" }
```

```json
{ "expo": { "locales": { "en": "./locales/en.json" } } }
```

Caution: a locale-qualified `expo_runtime_version` shadows the correct default for matching-locale devices, so the JSON must be bumped in lockstep with every release or it pins devices to a stale runtime.

## Additional context / suggested hypothesis

Upstream already has device-level proof of the mechanism in #48148 (open; SDK 55, second confirmation on SDK 57): Play Console's automatic app-string translation injects a locale-qualified `expo_runtime_version` server-side after upload, sourced from translation memory (in #48148: `1.2.1`, two months old, absent from the AAB). The code chain that lets it win:

1. `withRuntimeVersionResource` writes `<string name="expo_runtime_version">` into default `values/strings.xml` — [`packages/@expo/config-plugins/src/android/Updates.ts`](https://github.com/expo/expo/blob/main/packages/@expo/config-plugins/src/android/Updates.ts) (`applyRuntimeVersionFromConfigAsync`).
2. `setVersionsConfigAsync` writes the manifest entry as a reference: `expo.modules.updates.EXPO_RUNTIME_VERSION = @string/expo_runtime_version` (same file).
3. `UpdatesConfiguration.getRuntimeVersion()` resolves it at runtime via `context.getMetadataValue(...)`, i.e. with the device's current locale — [`packages/expo-updates/android/src/main/java/expo/modules/updates/UpdatesConfiguration.kt`](https://github.com/expo/expo/blob/main/packages/expo-updates/android/src/main/java/expo/modules/updates/UpdatesConfiguration.kt).

This MRE's local verification shows plain `expo prebuild` bakes the fresh value on clean **and** dirty prebuilds (`setStringItem` replaces in place — [`Strings.ts`](https://github.com/expo/expo/blob/main/packages/@expo/config-plugins/src/android/Strings.ts)), consistent with "the AAB was always correct" in #48148. Note `translatable="false"` cannot fix the Play path — [#48232](https://github.com/expo/expo/pull/48232)'s verify run measured that `aapt2` strips it, so it never reaches the bundle Play receives; the durable fixes proposed there are a literal manifest value or default-locale resolution in `expo-updates`.

Prior reports: #41694, #48148.
