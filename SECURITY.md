# Security & Data-Safety Policy

Because **JAM Cleaner** (`MacSweep`) inspects and removes files on macOS, **filesystem safety is treated as a security-critical boundary**. Any bug that could cause non-regenerable user data, credentials, or system state to be deleted or auto-selected is treated with the same severity as a security vulnerability.

---

## Supported Versions

| Version | Supported |
| :--- | :--- |
| `2.0.x` | :white_check_mark: Yes |
| `< 2.0.0` | :x: No |

---

## Built-In Safety Guarantees

JAM Cleaner enforces a **4-Layer Safety Guard Engine** (`Sources/MacSweepCore/Safety/`):

1. **Zero Privilege Escalation**:
   - JAM Cleaner runs strictly under the unprivileged user account (`geteuid()`).
   - It never invokes `sudo`, `SMJobBless`, or privileged root helper daemons.
   - `SafetyGuardEngine.isPathUserDeletable(_:)` rejects any file or directory owned by `root` (`uid 0`), system daemon accounts, or marked with `UF_IMMUTABLE` / `SF_IMMUTABLE` / SIP flags.

2. **Immutable & Credential Prefix Tree (`ExclusionPrefixTree`) + Deletion-Time TOCTOU Verification**:
   - Both raw standardized paths and symlink-resolved paths (`resolvingSymlinksInPath()`) are checked against `ExclusionPrefixTree` during scanning and re-verified immediately prior to deletion via `SafeTrashCleaner.isSafeToDeleteAtExecutionTime(path:)` (preventing Time-of-Check to Time-of-Use symlink swaps between scan and cleanup).
   - Protected roots that can **never** be scanned or deleted include:
     - `/System`, `/usr`, `/bin`, `/sbin`, `/Library/Apple`
     - `~/Library/Keychains`
     - `~/Library/Mobile Documents` (iCloud Drive) & `~/Library/CloudStorage` (Google Drive, OneDrive, Dropbox, Box)
     - `~/Library/Application Support/MobileSync` (iPhone/iPad local backups)
     - `~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.kube`, `~/.config`
     - `~/Documents`, `~/Desktop`, `~/Pictures`, `~/Movies`, `~/Music`
     - Apple system caches (`CloudKit`, `GeoServices`, `com.apple.metal`, `com.apple.ane`)
     - Active SQLite write-ahead logs and lock files (`*.db-wal`, `*.db-shm`, `*.sqlite-wal`, `lock`, `.lock`)

3. **Live Running Process Guard (`RunningProcessGuard`)**:
   - Detects running GUI applications (`NSWorkspace`) and BSD processes (`sysctl`) before cleaning.
   - Prompts the user to gracefully close open applications (`NSRunningApplication.terminate()`) before removing active caches.

4. **Strict Confidence Classification (`SafetyConfidence`)**:
   - `Safe Auto-Select` (`.safeAutoSelect`): Strictly regenerable caches, build artifacts, and logs.
   - `Review Recommended` (`.reviewRecommended`): Never auto-selected by default (e.g., local AI/LLM model weights in `~/.ollama/models` or `~/.cache/huggingface/hub`, iOS Simulator runtimes, and `.dmg`/`.pkg` installers in `~/Downloads`).

---

## What Qualifies as a Security / Data-Safety Vulnerability?

Please report any of the following immediately:
- **Exclusion Bypass / Symlink Traversal**: Any scenario where a symlink, firmlink, or relative path segment (`..`) allows `ScanOrchestrator` or `SafeTrashCleaner` to touch a path inside `ExclusionPrefixTree` or outside the user's intended target.
- **False-Positive `Safe Auto-Select` Classification**: Any rule in `Subscanners.swift` or `RuleKnowledgeBase.swift` that marks user documents, browser sessions/cookies/bookmarks, database state, or credentials as `.safeAutoSelect`.
- **TOCTOU (Time-of-Check to Time-of-Use) Race Conditions**: Any path between scan evaluation and `SafeTrashCleaner.execute(...)` that fails to re-verify safety invariants.

---

## Reporting a Vulnerability

- **Private Disclosure**: Please use **GitHub Private Vulnerability Reporting** (`Security › Advisories › Report a vulnerability` on the repository) rather than opening a public issue if the bug could cause accidental data loss or unauthorized file deletion.
- **What to Include**:
  - The affected path pattern (e.g. `~/Library/...`)
  - The subscanner or rule involved
  - Output from `swift run MacSweep --print-summary` or a minimal reproduction test case in `Tests/MacSweepTests/MacSweepTests.swift`
- **Response Timeline**:
  - We aim to acknowledge reports within **48 hours** and ship a verified fix + regression unit test in `MacSweepTests` within **7 days**.
