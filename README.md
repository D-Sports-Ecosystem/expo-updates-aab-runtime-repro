# MRE: Android AAB via Google Play embeds a STALE `expo-updates` runtimeVersion

Minimal repro for https://github.com/expo/expo/issues/41694 (closed for missing MRE — this is it).
Same mechanism as https://github.com/expo/expo/issues/48148 (open, with device-level proof).

Stock Expo SDK 57 blank app + `expo-updates`. No custom native code, no extra config, `expo-doctor` 21/21. The only deliberate config is the production-shaped updates setup: explicit string `runtimeVersion` (top level **and** `android.runtimeVersion`), `updates.url`, and the `expo-updates` plugin.

## The bug

After bumping `version`/`runtimeVersion` from A to B and rebuilding:

| Build | `Updates.runtimeVersion` on device |
|---|---|
| Android APK (EAS, sideloaded) | ✅ B (correct) |
| Android AAB → Google Play install | ❌ A (**stale**) |
| iOS | ✅ B (correct) |

The Play-installed app then rejects every OTA update published for runtime B with `updateRejectedBySelectionPolicy`, because its baked-in native runtime is still A.

In production this has pinned every Play build to runtime `1.24.3` while `app.json` says `1.28.0`.

## Repro, no Play account needed (local — shows what prebuild bakes in)

```sh
npm install
bash scripts/verify-local.sh
# Phase 1: clean prebuild at v1, grep expo_runtime_version  -> expect v1
# Phase 2: bump to v2, DIRTY prebuild (android/ kept)       -> expect v2 (tests caching/ordering)
# Phase 3: clean prebuild at v2                             -> expect v2
# Phase 4: locales shadowing demo (stale en.json)           -> qualified values-b+en shadows default
# Phase 5: restores app.json, leaves a clean v1 prebuild
```

What each step greps (equivalent one-liner after any `npx expo prebuild --platform android`):

```sh
grep -o '<string name="expo_runtime_version">[^<]*</string>' android/app/src/main/res/values/strings.xml
grep -o 'expo\.modules\.updates\.EXPO_RUNTIME_VERSION[^>]*' android/app/src/main/AndroidManifest.xml
```

## Repro, full (needs EAS + a Play internal track — Jon runs this)

```sh
npm install
bash scripts/configure-project.sh <your-eas-project-id>  # swaps YOUR-EAS-PROJECT-ID in app.json
bash scripts/repro-eas.sh            # dry run: prints every step
bash scripts/repro-eas.sh --execute  # runs the EAS builds
```

Exact sequence:

1. `eas build --platform android --profile apk` at v1 (`1.0.0`).
2. `bash scripts/bump-runtime.sh 2.0.0` — bumps `version`, top-level `runtimeVersion`, `android.runtimeVersion`, `versionCode`.
3. `eas build --platform android --profile apk` at v2 — sideload this APK (control arm).
4. `eas build --platform android --profile aab` at v2 — upload to Play Console → Internal testing (experimental arm). Before uploading, screenshot Play Console → Grow users → Translations → App strings (whether automatic app-string translation is on is the prime suspect — see hypothesis).
5. Install both v2 binaries on one device, open the app, screenshot the whole screen.
6. Expected: `Updates.runtimeVersion == 2.0.0` on both. Actual (bug): the Play build shows `1.0.0`.
7. Locale-switch test (discriminates Play-side injection): on the Play-installed build, switch device language (e.g. to English), reinstall from Play, and re-read `Updates.runtimeVersion`. If the stale value flips to correct, a locale-qualified split is overriding the default — exactly the #48148 signature.
8. Optional: `eas update --channel production` then relaunch both — the Play build rejects the update (`updateRejectedBySelectionPolicy`); the APK applies it.

Binary forensics without a device:

```sh
bash scripts/inspect-apk.sh <v2.apk>  # resources.arsc + assets/app.config
bash scripts/inspect-aab.sh <v2.aab>  # base/resources.pb + base/assets/app.config (+ bundletool if installed)
```

Device forensics (needs `adb` + the Play-installed build):

```sh
bash scripts/pull-device-splits.sh   # pulls base.apk + split_config.*.apk, greps each for expo_runtime_version
```

If the AAB already contains the stale value, it was baked at EAS build time; if the AAB is fresh but the Play-installed APK is stale, Play's signing/split serving is implicated.

## Expected vs actual

- Expected: `expo_runtime_version` in `strings.xml` / `resources.arsc`, and therefore `Updates.runtimeVersion` at runtime, equals the config's `android.runtimeVersion` (`2.0.0`) in **both** APK and Play-installed AAB builds.
- Actual: the Play-installed AAB build reports the **previous** version (`1.0.0`) while the APK is correct.

## Evidence (Jon's Play screenshots go here)

- [ ] v2 APK sideloaded — app screen showing `Updates.runtimeVersion = 2.0.0` → `evidence/apk-v2-correct.png`
- [ ] v2 AAB via Play internal track — app screen showing `Updates.runtimeVersion = 1.0.0` → `evidence/play-aab-v2-stale.png`
- [ ] Same Play build after switching device language to English + reinstall → `evidence/play-aab-v2-english.png`
- [ ] Play Console → Grow users → Translations → App strings (auto-translation on/off?) → `evidence/play-translation-setting.png`
- [ ] `bash scripts/pull-device-splits.sh` output (base vs `split_config.*.apk`) → `evidence/device-splits.txt`
- [ ] `adb logcat` / update manifest showing `updateRejectedBySelectionPolicy` on the Play build → `evidence/play-ota-rejected.log`
- [ ] `scripts/inspect-aab.sh` output for the v2 AAB → `evidence/inspect-aab-v2.txt`

## Workarounds

1. **Disable Play app-string translation** (confirmed fix in #48148): Play Console → Grow users → Translations → App strings → turn off automatic translation, then upload a **new** bundle. This does not clean already-published bundles — their injected translations persist, so a fresh upload is mandatory. Verify with `pull-device-splits.sh` that the locale split no longer defines `expo_runtime_version`.
2. **Pin `expo_runtime_version` through `locales` JSON** (the #41694 workaround; forces a locale-qualified value into the bundle that overwrites the translated one):

```json
// locales/en.json
{ "expo_runtime_version": "2.0.0" }
```

```json
{ "expo": { "locales": { "en": "./locales/en.json" } } }
```

⚠️ Sharp edge (demonstrated by `verify-local.sh` phase 4): a locale-qualified `expo_runtime_version` **shadows** the correct default for matching devices, so a forgotten bump in the JSON file pins those devices to a stale runtime forever. The workaround must be bumped in lockstep with every release.

## Environment that produced this repo

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

- `package-lock.json` pins all versions; `npx expo install --check` clean, `expo-doctor` 21/21.
- `android/` is gitignored (stock template); regenerate with `npx expo prebuild --platform android`.
- Triggering config mirrors production (SDK 57, explicit string `runtimeVersion` top-level + `android`, `updates.url`, `expo-updates` plugin, no `locales`). Generic bundle id `com.example.aabruntimerepro`; no secrets, no proprietary code.

## Suggested root-cause hypothesis (for upstream)

Upstream already has device-level proof of the mechanism in [#48148](https://github.com/expo/expo/issues/48148) (open; confirmed on SDK 55 and, by a second reporter, SDK 57): Google Play Console's automatic **app-string translation** (Gemini-powered, under Grow users → Translations → App strings) translates `expo_runtime_version` and injects a locale-qualified copy into the bundle **server-side, after upload**. That injected value comes from Play's translation memory — in #48148 it was `1.2.1`, the app version from two months earlier, a value that existed nowhere in the uploaded AAB. That matches this bug's signature exactly (production pinned at `1.24.3` across releases; APK correct; AAB stale).

The code chain that makes the injection win:

1. `withRuntimeVersionResource` writes `<string name="expo_runtime_version">` into default `values/strings.xml` from `android.runtimeVersion ?? runtimeVersion` — [Updates.ts](https://github.com/expo/expo/blob/main/packages/@expo/config-plugins/src/android/Updates.ts) (`applyRuntimeVersionFromConfigAsync`), resolution in [utils/Updates.ts](https://github.com/expo/expo/blob/main/packages/@expo/config-plugins/src/utils/Updates.ts) (`getRuntimeVersionAsync`).
2. `setVersionsConfigAsync` writes the manifest entry as a **reference**, not a literal: `expo.modules.updates.EXPO_RUNTIME_VERSION = @string/expo_runtime_version` — same [Updates.ts](https://github.com/expo/expo/blob/main/packages/@expo/config-plugins/src/android/Updates.ts). Wiring: [expo-updates withUpdates.ts](https://github.com/expo/expo/blob/main/packages/expo-updates/plugin/src/withUpdates.ts).
3. At runtime, `UpdatesConfiguration.getRuntimeVersion()` reads that meta-data via `context.getMetadataValue(...)`, which resolves `@string/expo_runtime_version` **with the device's current locale** — [UpdatesConfiguration.kt](https://github.com/expo/expo/blob/main/packages/expo-updates/android/src/main/java/expo/modules/updates/UpdatesConfiguration.kt). A locale-qualified copy therefore shadows the correct default on matching devices.
4. Since SDK 54, `withLocales` writes per-language `values-b+<lang>/strings.xml` from `locales` JSON — [Locales.ts](https://github.com/expo/expo/blob/main/packages/@expo/config-plugins/src/android/Locales.ts) (`setLocalesAsync`). Any `expo_runtime_version` key there (i.e. the #41694 workaround, if left unbumped) shadows the correct default the same way — demonstrated locally by `verify-local.sh` phase 4.

What this explains and what it doesn't:

- ✅ Explains APK-correct/AAB-stale (corruption happens during Play's processing of the bundle, not at build), iOS unaffected, the stale value predating the upload (translation memory), locale-dependent symptoms, and why the `locales` workaround "fixes" Play builds (it overwrites the translated value).
- ✅ Local prebuild verification (phases 1–3) bakes the fresh value on clean **and** dirty prebuilds — `setStringItem` replaces in place ([Strings.ts](https://github.com/expo/expo/blob/main/packages/@expo/config-plugins/src/android/Strings.ts)) — consistent with "the AAB was always correct" in #48148.
- ⚠️ `translatable="false"` is **not** a fix for the Play path: [#48232](https://github.com/expo/expo/pull/48232)'s verify run measured that `aapt2` strips the attribute during compilation, so it never reaches the `.aab` Play receives. The durable fixes proposed there are (a) writing the runtime literally into the manifest meta-data, or (b) resolving it in `expo-updates` against the default configuration instead of the device locale.
- 🔎 What Jon's run discriminates: `inspect-aab.sh` stale-in-AAB ⇒ build-time (EAS build-tools — note the *"ensure the same changes are also made in eas-cli and build-tools"* header in `Updates.ts`); fresh-in-AAB + stale-on-device + locale-switch flips it ⇒ Play translation, confirming #48148 on SDK 57 with an explicit-string runtime policy.

Prior reports: https://github.com/expo/expo/issues/41694, https://github.com/expo/expo/issues/48148.
Upstream issue draft (Jon files it): [ISSUE_DRAFT.md](./ISSUE_DRAFT.md).
