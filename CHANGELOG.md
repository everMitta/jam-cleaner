# Changelog

All notable changes to **JAM Cleaner** (`MacSweep`) are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [2.0.0] - 2026-10-26

### Added
- **JAM Cleaner Rebranding & Multi-Scope Architecture**:
  - Pre-scan scope selector allowing users to toggle **General**, **Developer**, and **AI** scan domains independently.
  - Dedicated **AI & Agent Runtimes** category inspecting Ollama (`~/.ollama/models` as `Review`, `~/.ollama/logs` as `Safe`), Hugging Face Hub (`~/.cache/huggingface/hub` as `Review`), LM Studio, PyTorch, Whisper, and Tiktoken caches.
- **4-Layer Safety Guard Engine**:
  - `SafetyGuardEngine` + `ExclusionPrefixTree` protecting Keychains, iCloud Drive, CloudStorage, MobileSync backups, SSH/AWS/GPG keys, active SQLite WAL/SHM journals, and Apple system caches (`CloudKit`, `GeoServices`, `Metal`).
  - `RunningProcessGuard` and `RunningAppCleanupCoordinator` to detect open applications and gracefully close them before cleaning active caches.
- **Honest APFS Physical Block Accounting**:
  - `DiskAllocatedSizeCalculator` measuring physical disk allocation (`NSURLTotalFileAllocatedSizeKey`) and `ScanAggregationEngine` deduplicating overlapping parent/child directories.
- **I/O- and Byte-Weighted Progress Telemetry**:
  - Monotonic I/O-cost-weighted progress tracking in `ScanOrchestrator` (`ScanProgressTracker`) and byte-plus-item-weighted progress in `SafeTrashCleaner`.
- **Trilingual Localization (`EN` | `ES` | `FR`)**:
  - Instant runtime language switching across English, Spanish, and French in `Localization.swift`.
- **Apple Distribution & Open Source Compliance**:
  - Bundled `Config/PrivacyInfo.xcprivacy` (Apple Required Reason API manifest with zero tracking and zero data collection).
  - Programmatic multi-resolution Retina `AppIcon.icns` generator (`scripts/generate_app_icon.swift`).
  - Open-source documentation (`README.md`, `LICENSE`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, `Makefile`, `.editorconfig`, `.swift-format`, and GitHub Actions CI + Issue/PR templates).
- **Strict Concurrency & Deletion-Time TOCTOU Hardening**:
  - Value-type `Sendable` `ExclusionPrefixTree` and compiler-verified `Sendable` conformance across `SafetyGuardEngine`, `ApplicationMetadataCatalog`, `ScanOrchestrator`, and `SafeTrashCleaner`.
  - `SafeTrashCleaner.isSafeToDeleteAtExecutionTime(path:)` re-verifies canonical symlink targets, protected cache components, and `SafetyGuardEngine.isPathUserDeletable` immediately prior to removal.
