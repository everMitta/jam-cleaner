# Contributing to JAM Cleaner

Thank you for your interest in contributing to **JAM Cleaner — Just another MacOS Cleaner** (`MacSweep`)!

Because a disk cleanup utility operates directly on user filesystems, **safety, transparency, and testability** are our highest priorities. This guide explains how to set up your environment, run tests, propose new cleanup rules safely, and submit pull requests.

---

## Table of Contents

1. [Code of Conduct](#code-of-conduct)
2. [Getting Started & Development Workflow](#getting-started--development-workflow)
3. [Golden Rules of Safety](#golden-rules-of-safety)
4. [How to Add a New Cache Rule or Scanner Target](#how-to-add-a-new-cache-rule-or-scanner-target)
5. [How to Add or Update Translations (`EN` / `ES` / `FR`)](#how-to-add-or-update-translations-en--es--fr)
6. [UI & Design Principles](#ui--design-principles)
7. [Submitting a Pull Request](#submitting-a-pull-request)

---

## Code of Conduct

This project adheres to the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

---

## Getting Started & Development Workflow

### Prerequisites
- macOS with Xcode or Xcode Command Line Tools (`swift --version`)

### Common Commands & Code Standardization

We provide a `Makefile`, `.editorconfig`, and `.swift-format` in the repository root for all everyday tasks:

```bash
# 1. Run the unit test suite (must pass before any PR)
make test

# 2. Run tests with LLVM code coverage report
make coverage

# 3. Validate Apple Privacy Manifest, Entitlements plist syntax, and zero-warning build
make lint

# 4. Format or check Swift code style (120-column line length, 4-space indent)
make format
make format-check

# 5. Build and package "build/JAM Cleaner.app"
make app

# 6. Build and launch the app
make run

# 7. Run a headless CLI scan summary in your terminal
make cli-summary
```

---

## Golden Rules of Safety

Every change to `Sources/MacSweepCore` must uphold these four invariants:

1. **Never Auto-Select Non-Regenerable User Data**:
   - `.safeAutoSelect` is strictly reserved for **100% regenerable caches, temporary build artifacts, and rotated logs** where deletion cannot lose user documents, credentials, sessions, or expensive downloads.
   - If recreating an artifact requires a multi-gigabyte download (e.g., local LLM weights in `~/.ollama/models` or `~/.cache/huggingface/hub`, iOS Simulator runtimes) or could discard user installers (`~/Downloads/*.dmg`), it **must** be classified as `.reviewRecommended`.
2. **Never Bypass `SafetyGuardEngine` or `ExclusionPrefixTree`**:
   - Every candidate `ScanItem` emitted by a subscanner must pass through `context.safetyEngine.evaluate(...)`.
   - Both the raw standardized path and symlink-resolved path (`resolvingSymlinksInPath()`) are checked against `ExclusionPrefixTree`.
3. **Never Require Root (`sudo`)**:
   - JAM Cleaner runs strictly as the logged-in user (`geteuid()`). Do not add rules or execution paths that invoke `sudo`, `AuthorizationExecuteWithPrivileges`, or privileged helper daemons.
4. **Always Deduplicate Parent & Child Paths**:
   - `ScanAggregationEngine.deduplicateOverlappingItems` ensures that if both a parent directory and its child subdirectory are discovered, their byte totals are never double-counted.

---

## How to Add a New Cache Rule or Scanner Target

1. **Choose the Right Subscanner**:
   Inspect `Sources/MacSweepCore/Scanners/Subscanners.swift`:
   - `ApplicationCachesSubscanner` — `~/Library/Caches` & app containers
   - `BrowserCachesSubscanner` — Web browser HTTP/GPU/Code caches
   - `DeveloperToolchainsSubscanner` — IDE, compiler, package manager, and AI/LLM caches
   - `ElectronAndWebAppRuntimeSubscanner` — Chromium/Electron `Cache`, `Code Cache`, `GPUCache`, and `CacheStorage`
   - `LogsAndDiagnosticsSubscanner` — Diagnostic reports and log directories
   - `PreferenceAndStateHygieneSubscanner` — Saved application states
   - `InstallerPackagesSubscanner` — Aged `.dmg` and `.pkg` installers

2. **Verify Protected Sibling Files**:
   When targeting a directory inside `~/Library/Application Support/<App>` or a browser profile, **only target the specific cache subdirectories** (`Cache`, `Code Cache`, `GPUCache`, `DawnCache`). Never target the parent profile folder containing `Cookies`, `Login Data`, `Bookmarks`, `Local Storage`, or `IndexedDB`.

3. **Add Unit Tests in `Tests/MacSweepTests/MacSweepTests.swift`**:
   - Add a positive test verifying the new path is allowed with the expected `SafetyConfidence` (`.safeAutoSelect` or `.reviewRecommended`).
   - If the target has sensitive sibling directories (e.g., credentials or models), add a test verifying those sensitive paths remain `.blocked` or `.reviewRecommended`.

---

## How to Add or Update Translations (`EN` / `ES` / `FR`)

All user-facing copy lives in [`Sources/MacSweepCore/Localization/Localization.swift`](Sources/MacSweepCore/Localization/Localization.swift):
- Every new `L10n` method or property must provide translations for all three supported languages in `AppLanguage`:
  - `.english` (`en`)
  - `.spanish` (`es`)
  - `.french` (`fr`)
- Add or update localization assertions in `Tests/MacSweepTests/MacSweepTests.swift` (`testLocalizationStringsAndLanguageSwitching`).

---

## UI & Design Principles

When modifying SwiftUI views in [`Sources/MacSweepApp/Views/MainDashboardView.swift`](Sources/MacSweepApp/Views/MainDashboardView.swift):
- **No Redundant Byte Counters**: State a metric once per visual region. For example, the primary CTA button (`Clean 15.97 GB`) already displays the selected byte total, so adjacent labels should show complementary metadata (`83 items selected`).
- **Exception-Only Badging**: Do not badge every row with a green `Safe` pill. Only badge items that require attention (`Review` or `Running`).
- **Sentence-Case Navigation**: Use native macOS sentence case (`Categories`, `General`, `Developer`, `AI`) rather than web-dashboard all-caps headers.
- **Clamped Monotonic Progress**: Any progress bar or percentage counter must clamp its fraction to `0.0...1.0` (`0...100%`) and avoid overlapping rolling digit transitions on high-frequency timers.

---

## Submitting a Pull Request

1. Fork the repository and create a feature branch (`git checkout -b feat/my-improvement`).
2. Run `make test` and `make lint` to confirm all tests and property lists pass.
3. Run `make app` to verify `JAM Cleaner.app` builds and signs cleanly.
4. Open a Pull Request and complete the checklist in `.github/PULL_REQUEST_TEMPLATE.md`.
