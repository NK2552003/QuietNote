# Contributing to QuietNote

Thank you for your interest in contributing to **QuietNote**! We welcome bug reports, feature suggestions, UI/UX polish, translations, and code contributions.

---

## Code of Conduct & Philosophy
QuietNote is designed as a calm, 100% private, offline-first study and productivity sanctuary.
When submitting proposals or code, keep these principles in mind:
1. **Zero Telemetry / 100% Privacy**: No tracking SDKs, no external sync servers, no ads.
2. **Offline-First**: All core features must function seamlessly without an internet connection.
3. **Calm & Distraction-Free UI**: Minimalist aesthetic, thoughtful whitespace, and smooth transitions.

---

## 🛠️ Development Setup

1. **Prerequisites**:
   - Flutter SDK ( `>=3.8.0 <4.0.0` )
   - Android Studio / Android SDK (API 34+)

2. **Clone & Install**:
   ```bash
   git clone https://github.com/NK2552003/QuietNote.git
   cd QuietNote
   flutter pub get
   ```

3. **Run Locally**:
   ```bash
   flutter run
   ```

4. **Verify Tests & Code Quality**:
   ```bash
   flutter analyze
   flutter test
   ```

---

## Submitting Pull Requests

1. **Fork the repository** on GitHub and create a new feature branch:
   ```bash
   git checkout -b feature/my-new-feature
   ```
2. **Make your changes** adhering to the existing codebase structure and design tokens.
3. **Add tests** in `test/` for new functionality.
4. **Ensure clean analysis**:
   ```bash
   flutter analyze
   flutter test
   ```
5. **Open a Pull Request** against `main` with a clear description of the changes.

---

## Reporting Bugs & Suggesting Features

- Open an issue on GitHub: [https://github.com/NK2552003/QuietNote/issues](https://github.com/NK2552003/QuietNote/issues)
- Provide clear reproduction steps, screenshots, and device/Android version info.
