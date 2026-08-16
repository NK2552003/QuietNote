# QuietNote

<p align="center">
  <img src="assets/branding/quietnote-logo.png" width="152" alt="QuietNote logo" />
</p>

<p align="center">
  <strong>A calm, private home for the things you want to remember.</strong><br />
  Notes, reflection, plans, and focus — thoughtfully organised and available offline.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.0%2B-202124?logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Platform-Android-202124?logo=android&logoColor=white" alt="Android" />
  <img src="https://img.shields.io/badge/Storage-On--device-202124?logo=sqlite&logoColor=white" alt="On-device storage" />
  <img src="https://img.shields.io/badge/AI-Optional%20%26%20local-202124" alt="Optional local AI" />
</p>

<p align="center">
  <a href="#start-here">Start here</a> ·
  <a href="#your-day-in-one-place">Features</a> ·
  <a href="#privacy-without-the-asterisk">Privacy</a> ·
  <a href="#project-map">Project map</a>
</p>

---

## A little more room to think

QuietNote is an offline-first productivity companion for the everyday
things worth holding onto: an idea before it disappears, a journal entry at
the end of a long day, a task for tomorrow, and an uninterrupted hour for the
work in front of you.

There is no account to create and no cloud connection required for your core
content. Just open the app and pick up where you left off.

## Your day, in one place

| Space | Made for |
| --- | --- |
| **Notes** | Capture ideas, checklists, rich text, images, and voice dictation. Every note opens in a clean, read-only preview before you choose to edit. |
| **Journal** | Write private, titled entries with moods and photos. Review past reflections through calm previews rather than an accidental editing state. |
| **Tasks & calendar** | Plan one-off or repeating work, events, due dates, and reminders. |
| **Habits, goals & routines** | Build momentum with streaks, milestones, daily progress, and repeatable rituals. |
| **Focus clock** | See what is next, then start a saved focus session with progress and completion alerts. |
| **AI Capture** | Turn a typed or spoken intention into useful local content when a compatible model is installed. |

### Designed to feel quiet

- **Readable at every size** — responsive navigation and card layouts adapt from compact phones to larger screens.
- **Preview before edit** — opening a note or journal tile takes you to a readable preview; editing is always a deliberate next step.
- **Helpful, never noisy** — useful empty states, loading feedback, and clear confirmations accompany everyday actions.
- **A considered visual language** — restrained grayscale branding and a consistent interface keep attention on your content.

## Privacy without the asterisk

Your notes, journal entries, tasks, habits, and focus records are stored in
local device storage. QuietNote is useful without a login or an internet
connection. Optional AI Capture uses on-device model files when you provide
them; the rest of the app works normally without AI enabled.

Some device permissions support specific features:

- **Notifications and alarms** for reminders and focus completion.
- **Microphone** for voice capture.
- **Photos/files** when you choose to attach an image or import content.

## Start here

### You will need

- Flutter SDK compatible with Dart `>=3.8.0 <4.0.0`
- Android Studio and an Android emulator or physical device

### Run the app

```bash
flutter pub get
flutter run
```

### Build a debug APK

```bash
flutter build apk --debug
```

The APK will be available at `build/app/outputs/flutter-apk/app-debug.apk`.

> **Optional local AI** — place compatible Gemma task files in
> `assets/models/` before building to enable AI Capture inference. The rest
> of QuietNote does not depend on these files.

## Project map

```text
lib/
├── core/              # Data, notifications, settings, navigation, shared UI
├── features/          # Notes, journal, tasks, habits, focus, AI, and more
└── main.dart          # Application entry point

assets/
├── branding/          # QuietNote PNG and SVG identity
└── models/            # Optional on-device AI model files (not committed)

fastlane/              # Store listing text
fdroid/                # F-Droid metadata template
docs/publishing/       # Release and publishing guidance
```

## Preparing a release & F-Droid

QuietNote is configured for F-Droid and standard Android releases. For release notes and version history, see the [Changelog](CHANGELOG.md).

For store publishing guidance and F-Droid metadata, read:
- [F-Droid Submission Guide](fdroid/README.md)
- [Complete Publishing Guide](docs/publishing/README.md)
- [Software License (Apache-2.0)](LICENSE)

---

<p align="center">
  <strong>Make room for what matters.</strong><br />
  Made for quieter, more intentional days.
</p>

