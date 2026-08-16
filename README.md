# QuietNote

<p align="center">
  <img src="assets/branding/quietnote-logo.png" width="140" alt="QuietNote logo" />
</p>

<p align="center">
  <strong>A calm, 100% private study suite and personal productivity sanctuary.</strong><br />
  Notes, reflection, habits, tasks, flashcards, and focus — thoughtfully organized and available offline.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/License-Apache--2.0-202124?style=flat-square" alt="Apache-2.0 License" />
  <img src="https://img.shields.io/badge/Platform-Android%208.0%2B-202124?logo=android&logoColor=white&style=flat-square" alt="Android 8.0+" />
  <img src="https://img.shields.io/badge/Flutter-3.8%2B-202124?logo=flutter&logoColor=white&style=flat-square" alt="Flutter" />
  <img src="https://img.shields.io/badge/F--Droid-Ready-202124?logo=f-droid&logoColor=white&style=flat-square" alt="F-Droid Ready" />
  <img src="https://img.shields.io/badge/Storage-100%25%20Local%20SQLite-202124?logo=sqlite&logoColor=white&style=flat-square" alt="100% Local SQLite" />
  <img src="https://img.shields.io/badge/AI-Optional%20%26%20Local-202124?style=flat-square" alt="Optional Local AI" />
  <img src="https://img.shields.io/badge/Telemetry-Zero%20Trackers-202124?style=flat-square" alt="Zero Telemetry" />
</p>

<p align="center">
  <a href="#core-features">Features</a> ·
  <a href="#privacy--security">Privacy & Security</a> ·
  <a href="#quick-start">Quick Start</a> ·
  <a href="#building-from-source">Building</a> ·
  <a href="#f-droid--publishing">F-Droid & Releases</a> ·
  <a href="#contributing">Contributing</a>
</p>

---

## A little more room to think

QuietNote is an offline-first productivity companion designed for deep work, study, and daily organization.

There are **no accounts to create**, **no subscription paywalls**, and **no remote cloud sync servers**. All your notes, journal entries, tasks, habits, flashcards, and focus records are stored safely in an on-device SQLite database.

---

## Core Features

| Domain | Description & Capabilities |
| :--- | :--- |
| **Study Notes & Markdown** | Distraction-free editor with CommonMark, LaTeX math equations (`$...$`, `$$...$$`), syntax highlighting for 150+ programming languages, tags, and instant PDF/Markdown exports. Opens in a read-only preview by default. |
| **To-dos & Tasks** | Streamlined task manager with priorities (Low, Medium, High, Urgent), due dates, and interactive checkbox subtasks. |
| **Habit Streaks** | Track consistency with consecutive day streak counters, daily targets, and visual streak heatmaps. |
| **Daily Routines** | Structured morning, afternoon, and evening routine workflow checklists. |
| **Reflective Journal** | Private daily reflection space with mood logs, gratitude prompts, and encrypted local storage. |
| **Spaced Repetition Flashcards** | Active recall flashcard study system with self-assessment recall grading (*Again*, *Hard*, *Good*, *Easy*). |
| **Courses & Syllabi** | Manage academic courses, lecture times, professors, and linked study materials in one hub. |
| **Goal Milestones** | Break ambitions down into measurable milestones with target completion dates and progress tracking. |
| **Zen Focus & Pomodoro** | Deep work timer with Pomodoro (25/5), 50/10, Deep Work (90 min), and custom interval presets, ambient bells, and an optional floating edge pill timer. |
| **Unified Timeline & Calendar** | Chronological timeline combining course lectures, exam dates, deadlines, and daily routines. |
| **Focus Clock & Alarms** | High-precision Android exact alarms synchronized with study blocks and morning routines. |
| **AI Capture & Assistant** | Optional on-device AI intent capture (local Gemma models) and BYOK cloud AI providers for note summarization, task extraction, and flashcard generation with zero telemetry. |

---

## Ergonomic Navigation Dock

* **Calibrated Sizes**: Choose between **Compact** (48dp), **Standard** (54dp), and **Spacious** (60dp) to match your screen size and preference.
* **Hand Alignment**: Align the floating dock to the **Left**, **Center**, or **Right** for comfortable one-handed reach with either thumb.
* **Interactive Live Preview**: Test dock sizing, hand alignment, and animated sliding pill indicators inside Appearance Settings.

---

## On-Device AI & Intent Capture (Optional)

QuietNote includes an optional, privacy-respecting AI assistant:
* **Fully Offline On-Device Gemma**: Run small language models (Gemma .task/.bin) directly on your device's hardware with zero data transmitted over the internet.
* **Bring Your Own Key (BYOK)**: Connect your own API key for cloud providers (OpenRouter, Gemini, Groq, Ollama) directly from the device.
* **No Telemetry**: AI queries are strictly processed locally or sent directly to your chosen API endpoint without passing through any intermediate proxy servers.
* **Works Without AI**: The entire QuietNote application functions 100% normally without any AI models or keys configured.

---

## Privacy & Security

* **100% Local Storage**: Powered by Drift and SQLite on your device.
* **Zero Telemetry**: Zero analytics frameworks, zero crash trackers, and zero advertising SDKs.
* **Native Biometric App Lock**: Secure your private notes and data with fingerprint, face unlock, or system PIN/pattern.
* **Full Data Ownership**: Export your entire database as JSON or backup notes as Markdown files anytime.

---

## Quick Start

### Prerequisites
* Flutter SDK (`>=3.8.0 <4.0.0`)
* Android Studio / Android SDK (API 26+)

### Run Locally
```bash
# Clone the repository
git clone https://github.com/NK2552003/QuietNote.git
cd QuietNote

# Install dependencies
flutter pub get

# Launch the app
flutter run
```

---

## Building from Source

### Lightweight Split APKs (~45 MB, Recommended)
```bash
flutter build apk --split-per-abi
```
Outputs optimized per-architecture APKs in `build/app/outputs/flutter-apk/`:
* `app-arm64-v8a-release.apk` (~45.6 MB · Modern Android smartphones)
* `app-armeabi-v7a-release.apk` (~40.0 MB · 32-bit Android phones)
* `app-x86_64-release.apk` (~48.7 MB · Emulators / Chromebooks)

### Universal Fat APK (~125 MB)
```bash
flutter build apk --release
```

---

## Project Structure

```text
lib/
├── core/
│   ├── branding/          # Logo and vector marks
│   ├── flutter-ui/        # Custom frosted UI kit and navigation dock
│   ├── focus/             # Focus timer and floating bubble service
│   ├── notifications/     # 11-feature notification taxonomy
│   ├── security/          # Biometric app lock gate and controller
│   └── settings/          # SQLite persistence and theme builder
├── features/              # Notes, journal, tasks, habits, courses, flashcards, etc.
└── main.dart              # Application entry point with root error dispatcher

fastlane/                  # Triple-T store metadata and 512x512 app icon
fdroid/                    # Production F-Droid metadata recipe
docs/                      # Release and publishing documentation
.github/                   # Issue forms, PR template, and security policy
```

---

## F-Droid & Publishing

QuietNote is fully prepared for open-source distribution:
* **Application ID**: `io.github.nk2552003.quietnote`
* **F-Droid Recipe**: [`fdroid/io.github.nk2552003.quietnote.yml`](fdroid/io.github.nk2552003.quietnote.yml)
* **In-Tree Config**: [`.fdroid.yml`](.fdroid.yml)
* **Publishing Guide**: [`docs/publishing/README.md`](docs/publishing/README.md)

---

## Documentation & Community

* **[Changelog](CHANGELOG.md)** — Version history and release notes.
* **[Contributing Guidelines](CONTRIBUTING.md)** — How to report bugs and submit pull requests.
* **[Security Policy](.github/SECURITY.md)** — Vulnerability reporting guidelines.
* **[License](LICENSE)** — Apache License 2.0.

---

<p align="center">
  <strong>Make room for what matters.</strong><br />
  Made for quieter, more intentional days.
</p>
