import Foundation

/// Execution mode for `SafeTrashCleaner`.
public enum CleanupExecutionMode: String, Sendable {
    /// Default mode: computes exact byte counts and verifies exclusion trees without modifying any file on disk.
    case dryRunPreview
    /// Moves selected items to the user's macOS Trash (`~/.Trash`) so any action can be undone.
    case moveToTrash
    /// Permanently removes selected regenerable caches and artifacts from disk to immediately reclaim APFS storage.
    case permanentDelete
}

/// Summary of a cleanup or dry-run execution pass.
public struct CleanupExecutionSummary: Sendable {
    public let mode: CleanupExecutionMode
    public let processedItemsCount: Int
    public let bytesReclaimed: UInt64
    public let skippedProtectedCount: Int
    public let errors: [String]
    public let cleanedItemIDs: Set<String>

    public init(
        mode: CleanupExecutionMode,
        processedItemsCount: Int,
        bytesReclaimed: UInt64,
        skippedProtectedCount: Int,
        errors: [String],
        cleanedItemIDs: Set<String> = []
    ) {
        self.mode = mode
        self.processedItemsCount = processedItemsCount
        self.bytesReclaimed = bytesReclaimed
        self.skippedProtectedCount = skippedProtectedCount
        self.errors = errors
        self.cleanedItemIDs = cleanedItemIDs
    }
}

/// Executes cleanup operations while enforcing the `SafetyGuardEngine` and `ExclusionPrefixTree` at removal time.
public final class SafeTrashCleaner: Sendable {
    public typealias TrashItemHandler = @Sendable (URL) throws -> Void

    public let safetyEngine: SafetyGuardEngine
    public let trashHandler: TrashItemHandler?

    public init(
        safetyEngine: SafetyGuardEngine = SafetyGuardEngine(),
        trashHandler: TrashItemHandler? = nil
    ) {
        self.safetyEngine = safetyEngine
        self.trashHandler = trashHandler
    }

    /// Re-verifies at deletion time that `path` (and its canonical symlink-resolved target) is not excluded,
    /// does not contain a protected Apple subsystem cache token, and is user-deletable.
    public func isSafeToDeleteAtExecutionTime(path: String) -> Bool {
        let standardized = ((path as NSString).expandingTildeInPath as NSString).standardizingPath
        let resolvedSymlink = URL(fileURLWithPath: standardized).resolvingSymlinksInPath().path

        if safetyEngine.exclusionTree.isPathOrAncestorExcluded(standardized)
            || (resolvedSymlink != standardized && safetyEngine.exclusionTree.isPathOrAncestorExcluded(resolvedSymlink))
        {
            return false
        }

        let allComponents =
            ExclusionPrefixTree.normalizedComponents(for: standardized)
            + (resolvedSymlink != standardized ? ExclusionPrefixTree.normalizedComponents(for: resolvedSymlink) : [])
        if allComponents.contains(where: { safetyEngine.rules.protectedCacheComponents.contains($0) }) {
            return false
        }

        return SafetyGuardEngine.isPathUserDeletable(standardized)
    }

    private func performSingleRemoval(
        atPath path: String, mode: CleanupExecutionMode, fileManager fm: FileManager
    ) throws {
        if mode == .moveToTrash {
            if let trashHandler {
                try trashHandler(URL(fileURLWithPath: path))
            } else {
                try fm.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
            }
        } else {
            try fm.removeItem(atPath: path)
        }
    }

    public func execute(
        items: [ScanCandidateItem],
        mode: CleanupExecutionMode = .dryRunPreview,
        fileManager fm: FileManager = .default,
        onProgressUpdate: ((Double, String) -> Void)? = nil
    ) -> CleanupExecutionSummary {
        var processed = 0
        var reclaimed: UInt64 = 0
        var skipped = 0
        var errors: [String] = []
        var cleanedIDs: Set<String> = []

        let selectedItems = items.filter(\.isSelected)
        let totalCount = max(selectedItems.count, 1)
        let totalSelectedBytes = selectedItems.reduce(UInt64(0)) { $0 + $1.allocatedBytes }
        var cumulativeBytes: UInt64 = 0

        func computeFraction(completedItems: Int, completedBytes: UInt64) -> Double {
            let itemRatio = min(1.0, max(0.0, Double(completedItems) / Double(totalCount)))
            guard totalSelectedBytes > 0 else { return itemRatio }
            let byteRatio = min(1.0, max(0.0, Double(completedBytes) / Double(totalSelectedBytes)))
            return min(1.0, max(0.0, (itemRatio * 0.35) + (byteRatio * 0.65)))
        }

        for (index, item) in selectedItems.enumerated() {
            let itemLabel = "\(item.appDisplayName) — \(item.itemName)"
            let startFraction = computeFraction(completedItems: index, completedBytes: cumulativeBytes)
            onProgressUpdate?(startFraction, itemLabel)
            cumulativeBytes += item.allocatedBytes
            let endFraction = computeFraction(completedItems: index + 1, completedBytes: cumulativeBytes)

            let standardized = ((item.path as NSString).expandingTildeInPath as NSString).standardizingPath

            // Re-verify against ExclusionPrefixTree, symlink-resolved targets, and deletability immediately prior to any filesystem action
            if item.confidence == .blocked || !isSafeToDeleteAtExecutionTime(path: standardized) {
                skipped += 1
                onProgressUpdate?(endFraction, itemLabel)
                continue
            }

            if mode == .dryRunPreview {
                processed += 1
                reclaimed += item.allocatedBytes
                cleanedIDs.insert(item.id)
                onProgressUpdate?(endFraction, itemLabel)
                continue
            }

            // If the path no longer exists on disk, treat it as already cleaned so stale entries are pruned
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: standardized, isDirectory: &isDir) else {
                processed += 1
                reclaimed += item.allocatedBytes
                cleanedIDs.insert(item.id)
                onProgressUpdate?(endFraction, itemLabel)
                continue
            }

            // If the directory contains a protected descendant, walk its children and only remove non-excluded children
            if safetyEngine.exclusionTree.hasExcludedDescendant(standardized) {
                if let children = try? fm.contentsOfDirectory(atPath: standardized) {
                    var anyChildFailed = false
                    for child in children {
                        let childPath = (standardized as NSString).appendingPathComponent(child)
                        if !isSafeToDeleteAtExecutionTime(path: childPath) {
                            skipped += 1
                            continue
                        }
                        do {
                            try performSingleRemoval(atPath: childPath, mode: mode, fileManager: fm)
                        } catch {
                            anyChildFailed = true
                            errors.append("\(childPath): \(error.localizedDescription)")
                        }
                    }
                    if !anyChildFailed || children.isEmpty {
                        processed += 1
                        reclaimed += item.allocatedBytes
                        cleanedIDs.insert(item.id)
                    }
                }
            } else {
                do {
                    try performSingleRemoval(atPath: standardized, mode: mode, fileManager: fm)
                    processed += 1
                    reclaimed += item.allocatedBytes
                    cleanedIDs.insert(item.id)
                } catch let topLevelError {
                    // Fallback for sandbox/container Caches directories where the parent folder is ACL-locked
                    // by macOS, but its inner cache entries can be removed normally.
                    if isDir.boolValue, let children = try? fm.contentsOfDirectory(atPath: standardized) {
                        var childRemovedCount = 0
                        var lastChildError: Error?
                        for child in children {
                            let childPath = (standardized as NSString).appendingPathComponent(child)
                            if !isSafeToDeleteAtExecutionTime(path: childPath) {
                                skipped += 1
                                continue
                            }
                            do {
                                try performSingleRemoval(atPath: childPath, mode: mode, fileManager: fm)
                                childRemovedCount += 1
                            } catch {
                                lastChildError = error
                            }
                        }
                        if childRemovedCount > 0 || children.isEmpty {
                            processed += 1
                            reclaimed += item.allocatedBytes
                            cleanedIDs.insert(item.id)
                        } else {
                            let errDesc = (lastChildError ?? topLevelError).localizedDescription
                            errors.append("\(standardized): \(errDesc)")
                        }
                    } else {
                        errors.append("\(standardized): \(topLevelError.localizedDescription)")
                    }
                }
            }

            onProgressUpdate?(endFraction, itemLabel)
        }

        return CleanupExecutionSummary(
            mode: mode,
            processedItemsCount: processed,
            bytesReclaimed: reclaimed,
            skippedProtectedCount: skipped,
            errors: errors,
            cleanedItemIDs: cleanedIDs
        )
    }
}
