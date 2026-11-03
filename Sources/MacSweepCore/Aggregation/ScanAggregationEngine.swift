import Foundation

/// Aggregates flat `ScanCandidateItem` detections into the 3-level hierarchy:
/// `CleanupCategoryGroup` (Level 1) -> `ApplicationBundleGroup` (Level 2) -> `ScanCandidateItem` (Level 3).
public enum ScanAggregationEngine {
    public static func aggregate(
        candidates: [ScanCandidateItem],
        appCatalog: ApplicationMetadataCatalog,
        scanDurationSeconds: Double,
        protectedPathsSkippedCount: Int
    ) -> ScanReport {
        // Deduplicate by canonical path so no file or directory is ever counted twice across subscanners.
        // Also enforce universal user-deletability as a final gate before any item can appear in the scan report.
        var uniqueByPath: [String: ScanCandidateItem] = [:]
        for item in candidates where item.allocatedBytes > 0 && item.confidence != .blocked {
            let canonical = ((item.path as NSString).expandingTildeInPath as NSString).standardizingPath
            guard SafetyGuardEngine.isPathUserDeletable(canonical) else { continue }
            if let existing = uniqueByPath[canonical] {
                if item.allocatedBytes > existing.allocatedBytes {
                    uniqueByPath[canonical] = item
                }
            } else {
                uniqueByPath[canonical] = item
            }
        }

        // Also ensure that if both a parent directory and a child directory are present, only the more specific or parent is kept without double counting.
        let sortedPaths = uniqueByPath.keys.sorted { $0.count < $1.count }
        var filteredItems: [ScanCandidateItem] = []
        var acceptedPrefixes: [String] = []

        for path in sortedPaths {
            let isDescendantOfAccepted = acceptedPrefixes.contains { prefix in
                path.hasPrefix(prefix + "/")
            }
            if !isDescendantOfAccepted, let item = uniqueByPath[path] {
                filteredItems.append(item)
                acceptedPrefixes.append(path)
            }
        }

        // Group by Category -> BundleIdentifier
        var byCategory: [CleanupCategory: [String: [ScanCandidateItem]]] = [:]
        for item in filteredItems {
            byCategory[item.category, default: [:]][item.bundleIdentifier, default: []].append(item)
        }

        var categoryGroups: [CleanupCategoryGroup] = []
        var runningSet = Set<String>()

        for category in CleanupCategory.allCases {
            guard let bundleMap = byCategory[category], !bundleMap.isEmpty else { continue }
            var appGroups: [ApplicationBundleGroup] = []

            for (bundleID, items) in bundleMap {
                let first = items[0]
                let resolved = appCatalog.resolve(folderOrBundleIdentifier: bundleID)
                let displayName = first.appDisplayName.isEmpty ? resolved.displayName : first.appDisplayName
                let isRunning = items.contains(where: \.isRunningApp)
                if isRunning {
                    runningSet.insert(bundleID)
                }

                let group = ApplicationBundleGroup(
                    category: category,
                    bundleIdentifier: bundleID,
                    appDisplayName: displayName,
                    bundlePath: resolved.bundlePath,
                    isRunning: isRunning,
                    items: items
                )
                appGroups.append(group)
            }

            let categoryGroup = CleanupCategoryGroup(
                category: category,
                appGroups: appGroups
            )
            categoryGroups.append(categoryGroup)
        }

        // Order categories by total reclaimable bytes descending
        categoryGroups.sort { $0.totalAllocatedBytes > $1.totalAllocatedBytes }

        return ScanReport(
            generatedAt: Date(),
            scanDurationSeconds: scanDurationSeconds,
            categories: categoryGroups,
            protectedPathsSkippedCount: protectedPathsSkippedCount,
            runningAppsDetectedCount: runningSet.count
        )
    }
}
