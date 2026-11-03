import Foundation

/// Thread-safe counter used to track concurrent subscanner completion progress weighted by I/O cost.
internal final class ScanProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var completedCount: Int = 0
    private var completedWeight: Double = 0.0
    private var highestFraction: Double = 0.04
    private let totalCount: Int
    private let totalWeight: Double

    init(subscanners: [CleanupSubscanner]) {
        self.totalCount = max(1, subscanners.count)
        let weightSum = subscanners.reduce(0.0) { $0 + $1.progressWeight }
        self.totalWeight = max(0.01, weightSum)
    }

    /// Returns the explicit I/O progress weight for a known subscanner identifier, or `nil` for custom subscanners.
    static func weight(for identifier: String) -> Double? {
        switch identifier {
        case "scanner.developer_toolchains":
            return 0.34
        case "scanner.app_caches":
            return 0.30
        case "scanner.electron_caches":
            return 0.12
        case "scanner.browser_caches":
            return 0.08
        case "scanner.logs_and_diagnostics":
            return 0.07
        case "scanner.prefs_and_state":
            return 0.05
        case "scanner.aged_installers":
            return 0.04
        default:
            return nil
        }
    }

    func recordMilestone(_ fraction: Double) -> Double {
        lock.lock()
        defer { lock.unlock() }
        let clamped = min(max(fraction, 0.0), 1.0)
        highestFraction = max(highestFraction, clamped)
        return highestFraction
    }

    func markSubscannerStarted() -> Double {
        lock.lock()
        defer { lock.unlock() }
        highestFraction = max(highestFraction, 0.10)
        return highestFraction
    }

    func markSubscannerCompleted(identifier: String) -> (completed: Int, total: Int, fraction: Double) {
        lock.lock()
        defer { lock.unlock() }
        completedCount += 1
        completedWeight += Self.weight(for: identifier) ?? 0.14
        let weightedRatio = min(1.0, completedWeight / totalWeight)
        let countRatio = min(1.0, Double(completedCount) / Double(totalCount))
        let blendedRatio = (weightedRatio * 0.75) + (countRatio * 0.25)
        let rawFraction = min(0.92, 0.10 + (blendedRatio * 0.82))
        highestFraction = max(highestFraction, rawFraction)
        return (completedCount, totalCount, highestFraction)
    }
}

/// Coordinates concurrent execution of all 7 cleanup subscanners, applies the 4-layer `SafetyGuardEngine`,
/// and builds the 3-level `ScanReport` via `ScanAggregationEngine`.
public final class ScanOrchestrator: Sendable {
    public let subscanners: [CleanupSubscanner]
    public let homeDirectoryPath: String

    public init(
        subscanners: [CleanupSubscanner]? = nil,
        homeDirectoryPath: String = NSHomeDirectory()
    ) {
        self.subscanners =
            subscanners ?? [
                ApplicationCacheSubscanner(),
                ElectronAndWebAppCacheSubscanner(),
                DeveloperToolchainSubscanner(),
                LogsAndDiagnosticsSubscanner(),
                BrowserCacheSubscanner(),
                PreferenceAndStateHygieneSubscanner(),
                InstallerPackageSubscanner(),
            ]
        self.homeDirectoryPath = homeDirectoryPath
    }

    /// Runs a full non-destructive scan and returns a hierarchical `ScanReport` filtered to `scopes`.
    public func runScan(
        scopes: Set<ScanScope> = Set(ScanScope.allCases),
        onProgressUpdate: (@Sendable (Double, String) -> Void)? = nil,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async -> ScanReport {
        let activeSubscanners = self.subscanners
        let tracker = ScanProgressTracker(subscanners: activeSubscanners)

        let emitProgress: @Sendable (Double, String) -> Void = { fraction, message in
            let monotonicFraction = tracker.recordMilestone(fraction)
            onProgressUpdate?(monotonicFraction, message)
            onProgress?(message)
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        emitProgress(0.04, "Indexing installed applications and active processes…")

        let safetyEngine = SafetyGuardEngine(homeDirectoryPath: homeDirectoryPath)
        let appCatalog = ApplicationMetadataCatalog(homeDirectoryPath: safetyEngine.homeDirectoryPath)

        emitProgress(0.08, "Launching \(activeSubscanners.count) parallel storage inspection modules…")

        let subscannerResults: [SubscannerResult] = await withTaskGroup(of: SubscannerResult.self) { group in
            for scanner in activeSubscanners {
                group.addTask {
                    let startFraction = tracker.markSubscannerStarted()
                    emitProgress(startFraction, "Scanning \(scanner.identifier)…")
                    let result = scanner.scan(safetyEngine: safetyEngine, appCatalog: appCatalog)
                    let progressState = tracker.markSubscannerCompleted(identifier: scanner.identifier)
                    emitProgress(
                        progressState.fraction,
                        "Completed \(scanner.identifier) (\(progressState.completed)/\(progressState.total))…"
                    )
                    return result
                }
            }

            var collected: [SubscannerResult] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        let allCandidates = subscannerResults.flatMap(\.candidates)
        let totalSkipped = subscannerResults.reduce(0) { $0 + $1.skippedProtectedCount }
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        emitProgress(0.96, "Aggregating \(allCandidates.count) detections into 3-level hierarchy…")
        let fullReport = ScanAggregationEngine.aggregate(
            candidates: allCandidates,
            appCatalog: appCatalog,
            scanDurationSeconds: elapsed,
            protectedPathsSkippedCount: totalSkipped
        )
        emitProgress(1.0, "Scan complete")
        return fullReport.filtered(by: scopes)
    }
}
