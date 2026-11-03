# JAM Cleaner (Just another MacOS Cleaner) — Apple Launch & Distribution Guide (`to_launch.md`)

This document outlines everything already automated in the repository for Apple compliance and the exact **manual steps** required on your Apple Developer account (`developer.apple.com` and App Store Connect) to ship **JAM Cleaner** (*Just another MacOS Cleaner*) via:

1. **Path A — Direct Distribution (Developer ID + Apple Notarization)** *(Recommended for full automated multi-domain filesystem scanning without per-folder prompts)*
2. **Path B — Mac App Store Distribution (App Sandbox + App Store Connect)**

---

## 1. Automated Apple Best Practices Already Configured in This Repo

The project build pipeline (`./scripts/build_app.sh`) and source code already implement the technical requirements enforced by Gatekeeper, Apple Notarization, and App Store Connect:

| Requirement | Status | Location in Repository |
| :--- | :--- | :--- |
| **Apple Privacy Manifest (Required Reason APIs)** | Automated | `Config/PrivacyInfo.xcprivacy` → bundled into `JAM Cleaner.app/Contents/Resources/PrivacyInfo.xcprivacy` (`NSPrivacyAccessedAPICategoryFileTimestamp`: `C617.1`, `DDA9.1`; `NSPrivacyAccessedAPICategoryDiskSpace`: `E174.1`, `85F4.1`; zero tracking). |
| **Multi-Resolution Retina `.icns` App Icon** | Automated | `scripts/generate_app_icon.swift` generates all 10 required macOS icon representations (`16x16` through `512x512@2x` / `1024×1024` sRGB PNGs) and compiles `JAM Cleaner.app/Contents/Resources/AppIcon.icns`. |
| **Complete `Info.plist` Metadata** | Automated | `scripts/build_app.sh` writes `CFBundleDisplayName` (`JAM Cleaner`), `CFBundleIdentifier` (`com.innoteclabs.jamcleaner`), `LSApplicationCategoryType` (`public.app-category.utilities`), `LSMinimumSystemVersion` (`26.0`), `NSHumanReadableCopyright`, `NSAppleEventsUsageDescription`, `NSSystemAdministrationUsageDescription`, and `CFBundleLocalizations` (`en`, `es`, `fr`). |
| **Hardened Runtime & Entitlements** | Automated | `Config/MacSweep.Direct.entitlements` (Hardened Runtime for Notarization) and `Config/MacSweep.AppStore.entitlements` (App Sandbox + `com.apple.security.files.user-selected.read-write` + `com.apple.security.files.bookmarks.app-scope`). |
| **Pre-Clean Running App Graceful Termination** | Automated | `Sources/MacSweepCore/Safety/RunningProcessGuard.swift` (`RunningAppCleanupCoordinator`) detects open GUI apps before cleaning and sends standard `NSRunningApplication.terminate()` events so open apps flush state cleanly before cache removal. |
| **Full Disk Access (TCC) Status & Deep-Link** | Automated | `FullDiskAccessPermissionHelper` checks TCC status non-destructively and deep-links to **System Settings › Privacy & Security › Full Disk Access** (`x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`). |
| **Native Single-Window App Lifecycle** | Automated | `MacSweepAppDelegate` implements `applicationShouldTerminateAfterLastWindowClosed(_:) -> true` per macOS Human Interface Guidelines for single-window utilities. |

---

## 2. Manual Prerequisite: Apple Developer Program & Certificates

Before distributing outside your local machine, complete these steps in your [Apple Developer Account](https://developer.apple.com/account):

1. **Register the App ID**:
   - Go to **Certificates, Identifiers & Profiles › Identifiers**.
   - Register an Explicit App ID with Bundle Identifier: `com.innoteclabs.jamcleaner`.
2. **Create Signing Certificates** (via **Xcode › Settings › Accounts › Manage Certificates**):
   - **For Direct Distribution (Outside the Mac App Store)**:
     - Create a **Developer ID Application** certificate (used to sign `.app` and `.dmg`).
     - Optional: Create a **Developer ID Installer** certificate (if distributing a `.pkg`).
   - **For Mac App Store Distribution**:
     - Create a **Mac App Distribution** certificate (or **Apple Distribution** certificate).
     - Create a **Mac Installer Distribution** certificate (required to sign the `.pkg` uploaded to App Store Connect).

Verify your installed signing identities in Terminal:

```bash
security find-identity -p codesigning -v
```

---

## 3. Building a Universal Binary (`arm64` + `x86_64`)

For production releases, Apple recommends shipping a Universal 2 binary supporting both Apple Silicon (`arm64`) and Intel (`x86_64`) Macs:

```bash
# From the repository root:
# Build both architectures in Release mode and package JAM Cleaner.app
BUILD_UNIVERSAL=1 \
SIGNING_IDENTITY="Developer ID Application: Innotec Labs (YOUR_TEAM_ID)" \
CHANNEL="direct" \
./scripts/build_app.sh
```

Verify the resulting universal binary and signature:

```bash
lipo -info "build/JAM Cleaner.app/Contents/MacOS/MacSweep"
codesign --verify --deep --strict --verbose=2 "build/JAM Cleaner.app"
plutil -lint "build/JAM Cleaner.app/Contents/Info.plist"
plutil -lint "build/JAM Cleaner.app/Contents/Resources/PrivacyInfo.xcprivacy"
```

---

## 4. Path A — Direct Distribution (Developer ID + Apple Notarization)

macOS Gatekeeper requires all Developer ID apps distributed outside the Mac App Store to be signed with the **Hardened Runtime** (`--options runtime`) and **notarized by Apple**.

### Step A1: Sign with Developer ID Application

```bash
SIGNING_IDENTITY="Developer ID Application: Innotec Labs (YOUR_TEAM_ID)" \
CHANNEL="direct" \
./scripts/build_app.sh
```

### Step A2: Store Notarization Credentials in Keychain (One-Time Setup)

Create an App-Specific Password at [appleid.apple.com](https://appleid.apple.com) and save it to your local Keychain profile:

```bash
xcrun notarytool store-credentials "JAMCleaner-Notary" \
  --apple-id "your-apple-id@example.com" \
  --team-id "YOUR_TEAM_ID" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

### Step A3: Submit for Apple Notarization & Staple the Ticket

```bash
# 1. Create a compressed archive for notarytool submission
ditto -c -k --keepParent "build/JAM Cleaner.app" build/JAMCleaner-notarize.zip

# 2. Submit to Apple Notary Service and wait for completion
xcrun notarytool submit build/JAMCleaner-notarize.zip \
  --keychain-profile "JAMCleaner-Notary" \
  --wait

# 3. Staple the notarization ticket directly to JAM Cleaner.app
xcrun stapler staple "build/JAM Cleaner.app"

# 4. Verify Gatekeeper acceptance
spctl --assess --type execute --verbose=4 "build/JAM Cleaner.app"
```

---

## 5. Path B — Mac App Store Submission (App Store Connect)

> **Important Architectural Note on App Store Guideline 2.4.5 (App Sandbox)**:
> Apple requires all Mac App Store apps to enable the **App Sandbox** (`com.apple.security.app-sandbox = true`) and does **not** grant broad home-directory temporary exceptions (`~/Library/Caches`, `~/.npm`, `~/.gradle`, etc.) unless the user explicitly selects the parent directory via a standard `NSOpenPanel` (`com.apple.security.files.user-selected.read-write`) and the app persists access using security-scoped bookmarks (`com.apple.security.files.bookmarks.app-scope`).
> - If you submit to the Mac App Store, prompt the user once on first scan with `NSOpenPanel` to grant read/write access to their home folder (`~`) or `~/Library` and store the resulting security-scoped bookmark.
> - Alternatively, many system utilities ship a **Direct Edition** (with full automated multi-domain scanning) and a **Mac App Store Edition** (using `NSOpenPanel` folder grants).

### Step B1: Download Provisioning Profile
1. In [Apple Developer Portal › Profiles](https://developer.apple.com/account/resources/certificates/list), create a **Mac App Store** provisioning profile for `com.innoteclabs.jamcleaner`.
2. Download the `.provisionprofile` and embed it at:
   `build/JAM Cleaner.app/Contents/embedded.provisionprofile`

### Step B2: Sign with App Store Entitlements & Build Installer `.pkg`

```bash
# 1. Build and sign the app bundle in App Store Sandbox mode
SIGNING_IDENTITY="Apple Distribution: Innotec Labs (YOUR_TEAM_ID)" \
CHANNEL="appstore" \
./scripts/build_app.sh

# 2. Build the signed .pkg installer for App Store Connect / Transporter
productbuild \
  --component "build/JAM Cleaner.app" /Applications \
  --sign "3rd Party Mac Developer Installer: Innotec Labs (YOUR_TEAM_ID)" \
  build/JAMCleaner-AppStore.pkg
```

### Step B3: Validate & Upload to App Store Connect

```bash
# Validate the package before uploading
xcrun altool --validate-app \
  -f build/JAMCleaner-AppStore.pkg \
  -t macos \
  -u "your-apple-id@example.com" \
  -p "@keychain:JAMCleaner-Notary"
```

Or open the **Transporter** macOS app from the Mac App Store, drag `build/JAMCleaner-AppStore.pkg` into the window, and click **Deliver**.

---

## 6. App Store Connect Metadata & Review Checklist

When creating the listing in [App Store Connect](https://appstoreconnect.apple.com), prepare the following assets manually:

1. **Primary Category**: `Utilities` (Secondary: `Developer Tools`).
2. **Age Rating**: `4+` (No objectionable content, no unrestricted web access).
3. **App Privacy Questionnaire**:
   - Select **"No, we do not collect data from this app"** (matches `Config/PrivacyInfo.xcprivacy` where `NSPrivacyCollectedDataTypes` is empty and `NSPrivacyTracking` is `false`).
4. **macOS Screenshots (16:10 Aspect Ratio)**:
   - Required sizes: `2880 × 1800` px (or `1440 × 900` px).
   - You can generate crisp Retina snapshots directly from the CLI and resize/pad them to `2880 × 1800`:
     ```bash
     "./build/JAM Cleaner.app/Contents/MacOS/MacSweep" --render-welcome-snapshot /tmp/welcome.png
     "./build/JAM Cleaner.app/Contents/MacOS/MacSweep" --render-scanning-snapshot /tmp/scanning.png
     "./build/JAM Cleaner.app/Contents/MacOS/MacSweep" --render-snapshot /tmp/results.png
     ```
5. **Support URL & Privacy Policy URL**:
   - Publish a public Support page and Privacy Policy page on your domain (e.g., `https://innoteclabs.com/macsweep/privacy`) stating that all storage inspection and cache cleanup executes 100% locally on the user's Mac with zero telemetry or cloud uploads.
6. **App Review Notes Template (Copy-Paste into App Store Connect)**:
   > MacSweep is a local storage and developer cache inspection utility for macOS.
   > - All scanning is user-initiated and non-destructive until the user explicitly clicks "Clean Now".
   > - Safe Auto-Selected items are strictly regenerable application, browser, and developer build caches.
   > - Items marked "Needs Review" (such as local LLM weights or iOS Simulator runtimes) are never auto-selected by default.
   > - A 4-layer safety engine protects active processes, system paths, browser profiles/bookmarks/cookies, and developer credentials.
   > - Zero user data or file metadata leaves the device.
