import Darwin
import Foundation

/// Verdict returned by the 4-layer Safety Guard Engine for a candidate path.
public struct SafetyEvaluationVerdict: Sendable {
    public let isAllowed: Bool
    public let confidence: SafetyConfidence
    public let isRunningApp: Bool
    public let reason: String

    public init(
        isAllowed: Bool,
        confidence: SafetyConfidence,
        isRunningApp: Bool,
        reason: String
    ) {
        self.isAllowed = isAllowed
        self.confidence = confidence
        self.isRunningApp = isRunningApp
        self.reason = reason
    }
}

/// Evaluates candidate paths across 4 independent safety layers:
/// 1. Immutable System & User Credential Root Guard
/// 2. Protected Cache & Subpath Prefix Tree (`ExclusionPrefixTree`)
/// 3. Live Process & Active Lock Guard (`RunningProcessGuard`)
/// 4. Confidence Tier Classifier (`SafeAutoSelect` vs `ReviewRecommended` vs `Blocked`)
public final class SafetyGuardEngine: Sendable {
    public let rules: RuleKnowledgeBase
    public let exclusionTree: ExclusionPrefixTree
    public let processGuard: RunningProcessGuard
    public let homeDirectoryPath: String

    public init(
        rules: RuleKnowledgeBase = .shared,
        processGuard: RunningProcessGuard = .captureCurrentSnapshot(),
        homeDirectoryPath: String = NSHomeDirectory()
    ) {
        self.rules = rules
        self.processGuard = processGuard
        let expandedHome = (homeDirectoryPath as NSString).expandingTildeInPath
        let standardizedHome = (expandedHome as NSString).standardizingPath
        let resolvedHome = URL(fileURLWithPath: standardizedHome).resolvingSymlinksInPath().path
        self.homeDirectoryPath = standardizedHome

        var allExcludedPaths: [String] = []
        allExcludedPaths.append(contentsOf: rules.immutableSystemRoots)

        for rel in rules.protectedHomeRelativeRoots {
            allExcludedPaths.append((standardizedHome as NSString).appendingPathComponent(rel))
            if resolvedHome != standardizedHome {
                allExcludedPaths.append((resolvedHome as NSString).appendingPathComponent(rel))
            }
        }

        // Also register protected cache subpaths inside ~/Library/Caches and /Library/Caches
        for component in rules.protectedCacheComponents {
            allExcludedPaths.append(
                (self.homeDirectoryPath as NSString).appendingPathComponent("Library/Caches/\(component)"))
            allExcludedPaths.append("/Library/Caches/\(component)")
            allExcludedPaths.append(
                (self.homeDirectoryPath as NSString).appendingPathComponent("Library/Logs/\(component)"))
            allExcludedPaths.append("/Library/Logs/\(component)")
            allExcludedPaths.append("/private/var/log/\(component)")
        }

        self.exclusionTree = ExclusionPrefixTree(excludedPaths: allExcludedPaths)
    }

    /// Evaluates whether a path is safe to surface in the cleanup preview and determines its confidence tier.
    public func evaluate(
        path: String,
        category: CleanupCategory,
        bundleIdentifier: String?,
        displayName: String?,
        processNames: [String] = [],
        defaultConfidence: SafetyConfidence = .safeAutoSelect,
        defaultReason: String
    ) -> SafetyEvaluationVerdict {
        let standardized = ((path as NSString).expandingTildeInPath as NSString).standardizingPath
        let resolvedSymlink = URL(fileURLWithPath: standardized).resolvingSymlinksInPath().path

        // Layer 1 & 2: Check exclusion prefix tree and protected path components (both raw and symlink-resolved)
        if exclusionTree.isPathOrAncestorExcluded(standardized)
            || (resolvedSymlink != standardized && exclusionTree.isPathOrAncestorExcluded(resolvedSymlink))
        {
            return SafetyEvaluationVerdict(
                isAllowed: false,
                confidence: .blocked,
                isRunningApp: false,
                reason: "Blocked by Protected Root / Cache Exclusion Guard"
            )
        }

        let pathComponents = ExclusionPrefixTree.normalizedComponents(for: standardized)
        let lastComponent = (standardized as NSString).lastPathComponent

        // Check if any component matches a protected cache token (e.g. CloudKit, GeoServices, Metal, ANE)
        for comp in pathComponents {
            if rules.protectedCacheComponents.contains(comp) {
                return SafetyEvaluationVerdict(
                    isAllowed: false,
                    confidence: .blocked,
                    isRunningApp: false,
                    reason: "Blocked: Protected Apple subsystem cache (\(comp))"
                )
            }
        }

        // Block any com.apple.* cache in /Library/Caches (system-level Apple caches)
        if standardized.hasPrefix("/Library/Caches/") && lastComponent.hasPrefix("com.apple.") {
            return SafetyEvaluationVerdict(
                isAllowed: false,
                confidence: .blocked,
                isRunningApp: false,
                reason: "Blocked: System-level Apple framework cache"
            )
        }

        // Block active SQLite WAL/SHM journal or lock files from standalone deletion
        let lowerLast = lastComponent.lowercased()
        if lowerLast.hasSuffix(".db-wal") || lowerLast.hasSuffix(".db-shm") || lowerLast.hasSuffix(".sqlite-wal")
            || lowerLast == "lock" || lowerLast == ".lock"
        {
            return SafetyEvaluationVerdict(
                isAllowed: false,
                confidence: .blocked,
                isRunningApp: false,
                reason: "Blocked: Active database write-ahead log or lock file"
            )
        }

        // Never allow arbitrary user files inside ~/Downloads unless they are verified aged installer packages (.dmg / .pkg)
        let downloadsRoot = (homeDirectoryPath as NSString).appendingPathComponent("Downloads")
        if standardized == downloadsRoot {
            return SafetyEvaluationVerdict(
                isAllowed: false,
                confidence: .blocked,
                isRunningApp: false,
                reason: "Blocked: Root ~/Downloads folder is never bulk-selected"
            )
        }
        if standardized.hasPrefix(downloadsRoot + "/") {
            let ext = (standardized as NSString).pathExtension.lowercased()
            if ext != "dmg" && ext != "pkg" {
                return SafetyEvaluationVerdict(
                    isAllowed: false,
                    confidence: .blocked,
                    isRunningApp: false,
                    reason: "Blocked: User file in ~/Downloads (only aged .dmg/.pkg installers are eligible)"
                )
            }
        }

        // Verify that if the path exists on disk, the current unprivileged user actually owns and can delete it
        if !Self.isPathUserDeletable(standardized) {
            return SafetyEvaluationVerdict(
                isAllowed: false,
                confidence: .blocked,
                isRunningApp: false,
                reason: "Blocked: File or directory is owned by root/system or is not deletable by the current user"
            )
        }

        // Layer 3: Check live process & running app state
        let isRunning = processGuard.isActive(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            processNames: processNames
        )

        // Layer 4: Confidence classification
        var finalConfidence = defaultConfidence
        var finalReason = defaultReason

        if category == .installerPackages {
            finalConfidence = .reviewRecommended
        } else if isRunning && (category == .browserCaches || category == .preferenceAndStateHygiene) {
            finalConfidence = .reviewRecommended
            finalReason =
                "\(defaultReason) (Application is currently running — JAM Cleaner will offer to close it gracefully before cleaning.)"
        } else if isRunning
            && (category == .webAndElectronCaches || category == .aiAndAgentRuntimes || category == .applicationCaches
                || category == .xcodeJunk)
        {
            finalReason =
                "\(defaultReason) (Application is currently running — JAM Cleaner can close it gracefully before cleaning to release active cache locks.)"
        }

        return SafetyEvaluationVerdict(
            isAllowed: true,
            confidence: finalConfidence,
            isRunningApp: isRunning,
            reason: finalReason
        )
    }

    /// Returns `true` if a path on disk is owned by the current user and can be deleted (or have its contents deleted)
    /// without root/elevated privileges. For synthetic non-existent unit test paths, returns `true` unless blocked by EACCES/EPERM.
    public static func isPathUserDeletable(
        _ path: String,
        effectiveUID: uid_t = geteuid()
    ) -> Bool {
        let standardized = ((path as NSString).expandingTildeInPath as NSString).standardizingPath
        var st = stat()
        guard lstat(standardized, &st) == 0 else {
            let err = errno
            if err == EACCES || err == EPERM {
                return false
            }
            return true
        }

        // Reject macOS immutable, append-only, or SIP-restricted files/directories (uchg / schg / restricted)
        let blockedFlags = UInt32(UF_IMMUTABLE | SF_IMMUTABLE | UF_APPEND | SF_APPEND) | 0x0008_0000
        if (st.st_flags & blockedFlags) != 0 {
            return false
        }

        if effectiveUID != 0 {
            // Reject files or directories owned by root (0) or system daemon accounts (_windowserver, _analyticsusers, etc.)
            if st.st_uid != effectiveUID {
                return false
            }

            let parentDir = (standardized as NSString).deletingLastPathComponent
            guard !parentDir.isEmpty, access(parentDir, W_OK | X_OK) == 0 else {
                return false
            }

            let isDir = (st.st_mode & S_IFMT) == S_IFDIR
            if isDir {
                guard access(standardized, R_OK | W_OK | X_OK) == 0 else {
                    return false
                }
            }
        }

        return true
    }
}
