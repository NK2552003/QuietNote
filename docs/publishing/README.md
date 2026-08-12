# Publishing QuietNote

This guide prepares QuietNote for both Google Play and F-Droid. Complete the shared release steps first, then follow the relevant store section.

> Do not publish with `com.example.quietnote`. Choose a unique application ID you control, such as `app.yourdomain.quietnote`, before the first public release. It cannot be changed in Google Play after publishing.

## 1. Release essentials

- Choose an open-source licence and add a `LICENSE` file at the repository root.
- Publish the full source code to a public Git repository.
- Replace the placeholder Android `namespace` and `applicationId` in `android/app/build.gradle.kts`.
- Update the app name, version name, and version code in `pubspec.yaml`.
- Create a private upload keystore; never commit it or its passwords.
- Test the release build on real Android devices: onboarding, notifications, exact alarms, focus completion after app closure, voice input, and all primary screens.

## 2. Create a signed Android App Bundle

Google Play accepts an Android App Bundle (`.aab`). Create a keystore once and store it securely:

```bash
keytool -genkey -v -keystore ~/quietnote-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias quietnote
```

Create `android/key.properties` locally (do not commit it):

```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=quietnote
storeFile=/absolute/path/to/quietnote-upload.jks
```

Configure the Android Gradle signing block to read this file, then produce the bundle:

```bash
flutter pub get
flutter build appbundle --release
```

The file is written to `build/app/outputs/bundle/release/app-release.aab`.

## Google Play

1. Create a Google Play Console developer account.
2. Create the QuietNote app using the final application ID and choose its category.
3. Upload the signed `.aab` to **Internal testing** first.
4. Complete the store listing: title, short description, full description, icon, feature graphic, screenshots, contact email, and privacy policy.
5. Complete the Data safety, Content rating, App access, Ads, and Target audience declarations honestly. QuietNote stores core content on-device; validate every declaration against the final build and any enabled AI/model feature.
6. Add the required permission declarations and explain their use in the Play Console: notifications, alarms/reminders, and microphone when voice input is included.
7. Test the internal track, promote to closed/open testing if needed, then create the production release.

Store copy is available in `fastlane/metadata/android/en-US/`.

## F-Droid

F-Droid distributes free and open-source Android applications built from publicly available source. It needs a public repository, an approved licence, reproducible build instructions, and no proprietary runtime dependency in the submitted build.

1. Complete every item in **Release essentials**.
2. Confirm each dependency is F-Droid-compatible. Review optional AI model delivery, analytics, and external services carefully.
3. Fill in every `TODO` in `fdroid/com.example.quietnote.yml.template` with the public repository, issue tracker, licence, version, and final application ID.
4. Submit the completed metadata and source repository through the F-Droid contribution process.
5. Work with the F-Droid build logs until the app builds reproducibly from source.

The `fdroid/` folder is intentionally a handoff template. It is not a publishing submission until its placeholders are replaced.

## Final release checklist

- [ ] Unique final application ID
- [ ] Version code increased
- [ ] Signing key safely backed up
- [ ] Store icons and screenshots updated
- [ ] Privacy policy published
- [ ] Notification and alarm behavior tested with the app closed
- [ ] Release bundle installed and smoke-tested
- [ ] Licence and public source repository ready
- [ ] F-Droid metadata has no TODO values

Once these are complete, QuietNote is ready for store review.
