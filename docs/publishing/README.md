# Publishing QuietNote

This guide documents the release and publishing workflow for QuietNote on Google Play and **F-Droid**.

## 1. Release Essentials (Configured)

- **Application ID / Namespace:** `io.github.nk2552003.quietnote`
- **Open-Source License:** Apache-2.0 ([`LICENSE`](../../LICENSE))
- **Source Code Repository:** `https://github.com/NK2552003/QuietNote`
- **Fastlane Triple-T Metadata:** [`fastlane/metadata/android/en-US/`](../../fastlane/metadata/android/en-US/)
- **F-Droid Recipe:** [`fdroid/io.github.nk2552003.quietnote.yml`](../../fdroid/io.github.nk2552003.quietnote.yml) and [`.fdroid.yml`](../../.fdroid.yml)

---

## 2. F-Droid Submission

F-Droid builds applications directly from public Git source using reproducible build environments.

### Submission Steps:
1. **Push release tag:**
   ```bash
   git tag -a v1.0.0 -m "Release v1.0.0"
   git push origin v1.0.0
   ```
2. **Fork `fdroiddata` on GitLab:**
   Fork [https://gitlab.com/fdroid/fdroiddata](https://gitlab.com/fdroid/fdroiddata).
3. **Copy metadata:**
   Place [`fdroid/io.github.nk2552003.quietnote.yml`](../../fdroid/io.github.nk2552003.quietnote.yml) into `metadata/io.github.nk2552003.quietnote.yml` on your fork.
4. **Open Merge Request:**
   Submit an MR to `fdroid/fdroiddata:master`. F-Droid CI will automatically build the APK and verify the release.

---

## 3. Google Play (Optional)

Google Play accepts signed Android App Bundles (`.aab`):

```bash
flutter build appbundle --release
```
The resulting file is at `build/app/outputs/bundle/release/app-release.aab`.

---

## 4. Local Build & Test

### Lightweight Split APKs (Recommended for GitHub Releases ~45MB)
```bash
flutter build apk --split-per-abi
```
Generates optimized per-architecture APKs in `build/app/outputs/flutter-apk/`:
- `app-arm64-v8a-release.apk` (**~45.6 MB** · Modern Android devices)
- `app-armeabi-v7a-release.apk` (**~40.0 MB** · Older 32-bit devices)
- `app-x86_64-release.apk` (**~48.7 MB** · Android emulators / Chromebooks)

### Universal Fat APK (All Architectures ~125MB)
```bash
flutter build apk --release
```
The universal APK is output to `build/app/outputs/flutter-apk/app-release.apk`.
