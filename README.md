<div align="center">
  <img src="assets/branding/monogram.svg" width="88" alt="Typed logo">

  # Typed

  **A quiet workspace for notes, tasks, and money.**

  Capture ideas, shape them into useful pages, and keep the details close.

  <p>
    <img src="https://img.shields.io/badge/Flutter-3.35.7-54C5F8?logo=flutter&logoColor=white" alt="Flutter 3.35.7">
    <img src="https://img.shields.io/badge/Dart-3.9.2-0175C2?logo=dart&logoColor=white" alt="Dart 3.9.2">
    <img src="https://img.shields.io/badge/storage-local--first-CC4D3C" alt="Local first">
    <img src="https://img.shields.io/badge/status-in%20development-6E7A85" alt="In development">
  </p>
</div>

---

## What is Typed?

Typed is a local-first notes and personal organization app for people who want one calm place for writing, checklists, and everyday finance tracking.

It is designed around a simple idea: notes should be easy to start, useful to return to, and structured enough to become part of your life.

## Highlights

| Notes | Tasks | Finance |
|:---:|:---:|:---:|
| Markdown editing, tags, pins, archive, trash, image capture, and reading mode | Interactive checklists, task filtering, quick capture, and persistent completion | Expenses, income, recurring entries, budgets, categories, periods, and CSV export |

### Built for focus

- Local-first storage with no account or backend required.
- Responsive layouts for desktop, mobile, and web.
- A compact workspace sidebar with notes, tasks, finance, tags, archive, and trash.
- Keyboard shortcuts, quick actions, templates, and command-oriented flows.
- Theme palettes, font choices, light/dark mode, and a restrained `t.` brand system.

### Built for real details

- Multiple currencies are surfaced instead of being silently combined.
- Recurring transactions preserve their type and metadata.
- JSON backups and finance CSV exports are supported.
- Android home-screen widgets expose quick capture, recent notes, and todos.
- Receipt OCR and image insertion are available on supported native platforms.

## Product Direction

Typed is moving toward an airy, editorial workspace inspired by the best parts of tools like Notion without becoming a clone:

- A collapsible workspace sidebar.
- A focused page editor with enhanced Markdown and slash commands.
- A collapsible context panel for properties, backlinks, and finance details.
- Quiet list rows instead of noisy card grids.
- Strong typography, subtle borders, and one deliberate accent color.

## Getting Started

### Requirements

- Flutter `3.35.7` or a compatible stable release.
- Dart `3.9.2` or newer within the project SDK constraint.
- Android Studio and an Android SDK for Android builds.
- Xcode for iOS and macOS builds.

### Install dependencies

```bash
flutter pub get
```

### Run locally

```bash
flutter run
```

For a specific target:

```bash
flutter run -d chrome
flutter run -d windows
flutter run -d <android-device-id>
```

### Run checks

```bash
flutter analyze
flutter test
```

### Build releases

```bash
flutter build web --release
flutter build apk --debug
```

The web output is generated at `build/web`. The debug APK is generated at `build/app/outputs/flutter-apk/app-debug.apk` and is suitable for local device testing.

Android release builds require a real signing configuration in `android/key.properties`. That file is intentionally not committed. Without it, use the debug build for testing or configure a production keystore before distributing an APK.

## Data and Privacy

Typed is local-first:

- Notes, tags, budgets, preferences, and finance data are stored on the device.
- There is no application account or hosted sync service.
- Backups are user-initiated exports.
- Deleting app data or uninstalling the app can remove locally stored notes unless they have been backed up.

## Project Structure

```text
lib/
├── main.dart                 # App entry point and theme setup
├── models/                   # Notes, budgets, and money entries
├── screens/                  # Top-level app screens
├── theme/                    # Palettes, typography, and theme controller
├── utils/                    # Persistence, backups, IDs, finance, and onboarding
└── widgets/                  # Editor, sidebar, lists, finance, and sheets

assets/branding/              # SVG brand sources
android/                      # Android app, widgets, splash, and signing config
ios/                          # iOS runner configuration
macos/                        # macOS runner configuration
web/                          # Flutter web shell and icons
test/                         # Dart and Flutter tests
```

## Brand

Typed uses a small, deliberate visual system:

- Mark: `t.`
- Accent: `#CC4D3C`
- Foreground: `#1A242E`
- Background: `#F8F9FA`
- Body type: DM Sans or the selected UI font
- Display type: Outfit or the selected display font
- Technical type: JetBrains Mono

The crossbar, stem, and foot use the foreground color. Only the period uses the red accent.

Brand sources live in `assets/branding/`, while the Flutter mark is rendered by `lib/widgets/brand_mark.dart`.

## Roadmap

- Enhanced Markdown and slash-command editing.
- Collapsible context panel and page properties.
- Command palette and faster keyboard workflows.
- Richer page hierarchy and backlinks.
- More complete cross-device backup and restore.
- Broader widget, accessibility, and integration test coverage.

## Status

Typed is an active work in progress. The core note, task, finance, backup, and responsive workspace flows are functional, while the broader design system and cross-platform release setup continue to evolve.

## License

No open-source license has been declared yet.

<div align="center">
  <sub>Made for thoughts worth keeping.</sub>
</div>
