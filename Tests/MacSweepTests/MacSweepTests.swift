import Foundation
import XCTest

@testable import MacSweepCore

final class MacSweepTests: XCTestCase {

    func testExclusionPrefixTreeAncestorAndDescendantChecks() {
        let tree = ExclusionPrefixTree(excludedPaths: [
            "/System",
            "/Users/testuser/Library/Keychains",
            "/Users/testuser/Library/Caches/CloudKit",
        ])

        // Direct and child paths under excluded roots must be blocked
        XCTAssertTrue(tree.isPathOrAncestorExcluded("/System"))
        XCTAssertTrue(tree.isPathOrAncestorExcluded("/System/Library/CoreServices"))
        XCTAssertTrue(tree.isPathOrAncestorExcluded("/Users/testuser/Library/Keychains/login.keychain-db"))
        XCTAssertTrue(tree.isPathOrAncestorExcluded("/Users/testuser/Library/Caches/CloudKit/metadata"))

        // Sibling cache folder should NOT be excluded
        XCTAssertFalse(tree.isPathOrAncestorExcluded("/Users/testuser/Library/Caches/com.example.app"))

        // Parent folder `/Users/testuser/Library/Caches` has an excluded descendant (`CloudKit`), so bulk removal must be flagged
        XCTAssertTrue(tree.hasExcludedDescendant("/Users/testuser/Library/Caches"))
        XCTAssertFalse(tree.hasExcludedDescendant("/Users/testuser/Library/Caches/com.example.app"))
    }

    func testSafetyGuardEngineBlocksCriticalSystemAndUserPaths() {
        let mockProcessGuard = RunningProcessGuard(
            runningBundleIdentifiers: ["com.google.chrome"],
            runningLocalizedAppNames: ["google chrome"],
            runningProcessExecutables: ["chrome"]
        )
        let engine = SafetyGuardEngine(
            rules: .shared,
            processGuard: mockProcessGuard,
            homeDirectoryPath: "/Users/testuser"
        )

        let blockedPaths = [
            "/System/Library/Caches/com.apple.kernelcaches",
            "/Users/testuser/Library/Keychains/login.keychain-db",
            "/Users/testuser/Library/CloudStorage/GoogleDrive/My Drive/file.txt",
            "/Users/testuser/Library/Mobile Documents/com~apple~CloudDocs/doc.pages",
            "/Users/testuser/.ssh/id_ed25519",
            "/Users/testuser/.aws/credentials",
            "/Users/testuser/Documents/Financials.xlsx",
            "/Users/testuser/Library/Caches/CloudKit/records.db",
            "/Users/testuser/Library/Caches/GeoServices/tiles",
            "/Users/testuser/Library/Caches/com.apple.metal/shaders",
            "/Library/Caches/com.apple.iconservices.store",
            "/Users/testuser/Library/Caches/com.example.app/database.db-wal",
            "/Users/testuser/Downloads",
            "/Users/testuser/Downloads/ImportantContract.pdf",
        ]

        for path in blockedPaths {
            let verdict = engine.evaluate(
                path: path,
                category: .applicationCaches,
                bundleIdentifier: "com.example.app",
                displayName: "Example",
                defaultReason: "Test"
            )
            XCTAssertFalse(verdict.isAllowed, "Expected path to be hard-blocked by SafetyGuardEngine: \(path)")
            XCTAssertEqual(verdict.confidence, .blocked)
        }
    }

    func testSafetyGuardAllowsSafeCachesAndClassifiesConfidence() {
        let mockProcessGuard = RunningProcessGuard(
            runningBundleIdentifiers: ["com.google.chrome"],
            runningLocalizedAppNames: ["google chrome"],
            runningProcessExecutables: ["chrome"]
        )
        let engine = SafetyGuardEngine(
            rules: .shared,
            processGuard: mockProcessGuard,
            homeDirectoryPath: "/Users/testuser"
        )

        // 1. Standard non-running application cache -> .safeAutoSelect
        let appCacheVerdict = engine.evaluate(
            path: "/Users/testuser/Library/Caches/org.example.editor",
            category: .applicationCaches,
            bundleIdentifier: "org.example.editor",
            displayName: "Example Editor",
            defaultReason: "Regenerable app cache"
        )
        XCTAssertTrue(appCacheVerdict.isAllowed)
        XCTAssertEqual(appCacheVerdict.confidence, .safeAutoSelect)
        XCTAssertFalse(appCacheVerdict.isRunningApp)

        // 2. Running browser cache -> downgraded to .reviewRecommended
        let runningBrowserVerdict = engine.evaluate(
            path: "/Users/testuser/Library/Caches/Google/Chrome",
            category: .browserCaches,
            bundleIdentifier: "com.google.Chrome",
            displayName: "Google Chrome",
            defaultReason: "Browser cache"
        )
        XCTAssertTrue(runningBrowserVerdict.isAllowed)
        XCTAssertTrue(runningBrowserVerdict.isRunningApp)
        XCTAssertEqual(runningBrowserVerdict.confidence, .reviewRecommended)

        // 3. Aged .dmg installer in ~/Downloads -> .reviewRecommended
        let dmgVerdict = engine.evaluate(
            path: "/Users/testuser/Downloads/OldInstaller.dmg",
            category: .installerPackages,
            bundleIdentifier: "macos.installer.dmg",
            displayName: "Installer",
            defaultReason: "Aged installer"
        )
        XCTAssertTrue(dmgVerdict.isAllowed)
        XCTAssertEqual(dmgVerdict.confidence, .reviewRecommended)
    }

    func testCorruptedPropertyListDetection() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let validPlistURL = tempDir.appendingPathComponent("valid.plist")
        let validDict: NSDictionary = ["Key": "Value", "Number": 42]
        try validDict.write(to: validPlistURL)
        XCTAssertFalse(PreferenceAndStateHygieneSubscanner.isCorruptedPropertyList(atPath: validPlistURL.path))

        let corruptedPlistURL = tempDir.appendingPathComponent("corrupted.plist")
        try Data("<?xml version=\"1.0\"?><plist><dict><key>Unclosed".utf8).write(to: corruptedPlistURL)
        XCTAssertTrue(PreferenceAndStateHygieneSubscanner.isCorruptedPropertyList(atPath: corruptedPlistURL.path))

        let emptyPlistURL = tempDir.appendingPathComponent("empty.plist")
        try Data().write(to: emptyPlistURL)
        XCTAssertTrue(PreferenceAndStateHygieneSubscanner.isCorruptedPropertyList(atPath: emptyPlistURL.path))
    }

    func testAggregationDeduplicatesNestedPaths() {
        let parentItem = ScanCandidateItem(
            path: "/Users/testuser/Library/Application Support/ExampleApp/Cache",
            category: .webAndElectronCaches,
            bundleIdentifier: "com.example.app",
            appDisplayName: "ExampleApp",
            itemName: "Cache",
            allocatedBytes: 100_000,
            fileCount: 50,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: false,
            ruleIdentifier: "r1",
            safetyExplanation: "Parent cache"
        )
        let childItem = ScanCandidateItem(
            path: "/Users/testuser/Library/Application Support/ExampleApp/Cache/Cache_Data",
            category: .webAndElectronCaches,
            bundleIdentifier: "com.example.app",
            appDisplayName: "ExampleApp",
            itemName: "Cache_Data",
            allocatedBytes: 95_000,
            fileCount: 45,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: false,
            ruleIdentifier: "r2",
            safetyExplanation: "Child cache"
        )

        let catalog = ApplicationMetadataCatalog(homeDirectoryPath: "/Users/testuser")
        let report = ScanAggregationEngine.aggregate(
            candidates: [parentItem, childItem],
            appCatalog: catalog,
            scanDurationSeconds: 0.1,
            protectedPathsSkippedCount: 5
        )

        XCTAssertEqual(
            report.grandTotalBytes, 100_000,
            "Nested child path must not be double-counted on top of its parent directory")
        XCTAssertEqual(report.totalCandidateCount, 1)
    }

    func testScanScopeFilteringAndAICategoryUpgrade() {
        let generalItem = ScanCandidateItem(
            path: "/Users/testuser/Library/Caches/com.apple.Safari",
            category: .browserCaches,
            bundleIdentifier: "com.apple.Safari",
            appDisplayName: "Safari",
            itemName: "Safari Cache",
            allocatedBytes: 50_000_000,
            fileCount: 120,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: false,
            ruleIdentifier: "browser.safari",
            safetyExplanation: "Browser cache"
        )
        let devItem = ScanCandidateItem(
            path: "/Users/testuser/Library/Developer/Xcode/DerivedData",
            category: .xcodeJunk,
            bundleIdentifier: "com.apple.dt.Xcode",
            appDisplayName: "Xcode",
            itemName: "DerivedData",
            allocatedBytes: 200_000_000,
            fileCount: 500,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: false,
            ruleIdentifier: "dev.xcode_derived_data",
            safetyExplanation: "Xcode build cache"
        )
        let legacyAICandidate = ScanCandidateItem(
            path: "/Users/testuser/.cache/puppeteer",
            category: .developerToolchains,
            bundleIdentifier: "dev.puppeteer",
            appDisplayName: "Puppeteer",
            itemName: "Browser Runtimes",
            allocatedBytes: 120_000_000,
            fileCount: 40,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: false,
            ruleIdentifier: "dev.puppeteer_cache",
            safetyExplanation: "Headless browser runtime"
        )

        let catalog = ApplicationMetadataCatalog(homeDirectoryPath: "/Users/testuser")
        let initialReport = ScanAggregationEngine.aggregate(
            candidates: [generalItem, devItem, legacyAICandidate],
            appCatalog: catalog,
            scanDurationSeconds: 0.2,
            protectedPathsSkippedCount: 10
        )

        let upgraded = initialReport.upgradedWithAICategory()
        XCTAssertEqual(upgraded.totalBytes(for: .general), 50_000_000)
        XCTAssertEqual(upgraded.totalBytes(for: .developer), 200_000_000)
        XCTAssertEqual(upgraded.totalBytes(for: .ai), 120_000_000)

        let aiOnlyReport = upgraded.filtered(by: Set<ScanScope>([.ai]))
        XCTAssertEqual(aiOnlyReport.categories.count, 1)
        XCTAssertEqual(aiOnlyReport.categories.first?.category, CleanupCategory.aiAndAgentRuntimes)
        XCTAssertEqual(aiOnlyReport.grandTotalBytes, 120_000_000)
    }

    func testSystemDefaultLanguageDetectionAndLocalization() {
        XCTAssertEqual(AppLanguage.systemDefault(preferredLanguages: ["es-ES", "en-US"]), .spanish)
        XCTAssertEqual(AppLanguage.systemDefault(preferredLanguages: ["es-419"]), .spanish)
        XCTAssertEqual(AppLanguage.systemDefault(preferredLanguages: ["fr-FR", "en-US"]), .french)
        XCTAssertEqual(AppLanguage.systemDefault(preferredLanguages: ["fr-CA"]), .french)
        XCTAssertEqual(AppLanguage.systemDefault(preferredLanguages: ["en-US", "es-ES"]), .english)
        XCTAssertEqual(AppLanguage.systemDefault(preferredLanguages: ["de-DE"]), .english)

        // Verify localized scope titles and short descriptions in all 3 languages
        for lang in AppLanguage.allCases {
            for scope in ScanScope.allCases {
                XCTAssertFalse(scope.title(in: lang).isEmpty)
                XCTAssertFalse(scope.shortDescription(in: lang).isEmpty)
            }
            for category in CleanupCategory.allCases {
                XCTAssertFalse(category.title(in: lang).isEmpty)
                XCTAssertFalse(category.subtitle(in: lang).isEmpty)
            }
        }

        XCTAssertEqual(ScanScope.general.title(in: .english), "General")
        XCTAssertEqual(ScanScope.developer.title(in: .spanish), "Desarrollador")
        XCTAssertEqual(ScanScope.developer.title(in: .french), "Développeur")
        XCTAssertEqual(L10n.startScanButton(.english), "Start Scan")
        XCTAssertEqual(L10n.startScanButton(.spanish), "Iniciar análisis")
        XCTAssertEqual(L10n.startScanButton(.french), "Lancer l’analyse")
    }

    func testWholeCategoryAndScopeSelectionState() {
        let generalItem = ScanCandidateItem(
            path: "/Users/testuser/Library/Caches/com.apple.Safari",
            category: .browserCaches,
            bundleIdentifier: "com.apple.Safari",
            appDisplayName: "Safari",
            itemName: "Safari Cache",
            allocatedBytes: 50_000_000,
            fileCount: 120,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: false,
            ruleIdentifier: "browser.safari",
            safetyExplanation: "Browser cache"
        )
        let devItem = ScanCandidateItem(
            path: "/Users/testuser/Library/Developer/Xcode/DerivedData",
            category: .xcodeJunk,
            bundleIdentifier: "com.apple.dt.Xcode",
            appDisplayName: "Xcode",
            itemName: "DerivedData",
            allocatedBytes: 200_000_000,
            fileCount: 500,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: false,
            ruleIdentifier: "dev.xcode_derived_data",
            safetyExplanation: "Xcode build cache"
        )
        let aiItem = ScanCandidateItem(
            path: "/Users/testuser/.ollama/models",
            category: .aiAndAgentRuntimes,
            bundleIdentifier: "ai.ollama.models",
            appDisplayName: "Ollama",
            itemName: "LLM Weights",
            allocatedBytes: 400_000_000,
            fileCount: 18,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: false,
            ruleIdentifier: "ai.ollama_models",
            safetyExplanation: "Local LLM weights"
        )

        let catalog = ApplicationMetadataCatalog(homeDirectoryPath: "/Users/testuser")
        var sample = ScanAggregationEngine.aggregate(
            candidates: [generalItem, devItem, aiItem],
            appCatalog: catalog,
            scanDurationSeconds: 0.1,
            protectedPathsSkippedCount: 4
        )

        // Verify categories are divided into the 3 scopes (General, Developer, AI)
        let generalCategories = sample.categories(for: .general)
        let devCategories = sample.categories(for: .developer)
        let aiCategories = sample.categories(for: .ai)
        XCTAssertEqual(generalCategories.count, 1)
        XCTAssertEqual(devCategories.count, 1)
        XCTAssertEqual(aiCategories.count, 1)
        XCTAssertTrue(sample.isScopeAllSelected(.general))
        XCTAssertTrue(sample.isScopeAllSelected(.developer))
        XCTAssertTrue(sample.isScopeAllSelected(.ai))

        // Unselect an entire cleanup domain and verify isAllSelected / isPartiallySelected / selectedAllocatedBytes
        guard let firstCatIdx = sample.categories.indices.first else {
            XCTFail("Expected at least one category")
            return
        }
        let unselectedScope = sample.categories[firstCatIdx].category.scope
        for grpIdx in sample.categories[firstCatIdx].appGroups.indices {
            for itemIdx in sample.categories[firstCatIdx].appGroups[grpIdx].items.indices {
                sample.categories[firstCatIdx].appGroups[grpIdx].items[itemIdx].isSelected = false
            }
        }
        XCTAssertFalse(sample.categories[firstCatIdx].isAllSelected)
        XCTAssertFalse(sample.categories[firstCatIdx].isPartiallySelected)
        XCTAssertEqual(sample.categories[firstCatIdx].selectedAllocatedBytes, 0)
        XCTAssertFalse(sample.isScopeAllSelected(unselectedScope))
        XCTAssertFalse(sample.isScopePartiallySelected(unselectedScope))

        // Select all items in that cleanup domain
        for grpIdx in sample.categories[firstCatIdx].appGroups.indices {
            for itemIdx in sample.categories[firstCatIdx].appGroups[grpIdx].items.indices {
                sample.categories[firstCatIdx].appGroups[grpIdx].items[itemIdx].isSelected = true
            }
        }
        XCTAssertTrue(sample.categories[firstCatIdx].isAllSelected)
        XCTAssertFalse(sample.categories[firstCatIdx].isPartiallySelected)
        XCTAssertEqual(
            sample.categories[firstCatIdx].selectedAllocatedBytes,
            sample.categories[firstCatIdx].totalAllocatedBytes
        )
        XCTAssertTrue(sample.isScopeAllSelected(unselectedScope))
    }

    func testScanningProgressStringsAndLocalization() {
        for lang in AppLanguage.allCases {
            XCTAssertFalse(L10n.scanningInProgressTitle(lang).isEmpty)
            XCTAssertFalse(L10n.scanningInProgressSubtitle(lang).isEmpty)
            XCTAssertFalse(L10n.scanningElapsedBadge(seconds: 4.2, language: lang).isEmpty)
        }
        XCTAssertEqual(
            L10n.localizedProgressStage("Completed Developer Caches", language: .spanish),
            "Completado: Developer Caches"
        )
        XCTAssertEqual(
            L10n.localizedProgressStage("Completed Developer Caches", language: .french),
            "Terminé : Developer Caches"
        )
        XCTAssertEqual(
            L10n.localizedProgressStage("Aggregating and deduplicating scan report...", language: .spanish),
            "Agrupando detecciones en jerarquía de 3 niveles…"
        )
    }

    func testConfidenceFilterAndUnselectAllReviewItems() {
        let safeItem = ScanCandidateItem(
            path: "/Users/testuser/.ollama/logs",
            category: .aiAndAgentRuntimes,
            bundleIdentifier: "ai.ollama.logs",
            appDisplayName: "Ollama Logs",
            itemName: "Server Logs",
            allocatedBytes: 40_000_000,
            fileCount: 12,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: false,
            ruleIdentifier: "ai.ollama_logs",
            safetyExplanation: "Regenerated logs"
        )
        let reviewItem = ScanCandidateItem(
            path: "/Users/testuser/.ollama/models",
            category: .aiAndAgentRuntimes,
            bundleIdentifier: "ai.ollama.models",
            appDisplayName: "Ollama Models",
            itemName: "LLM Weights",
            allocatedBytes: 600_000_000,
            fileCount: 25,
            lastModified: Date(),
            confidence: .reviewRecommended,
            isRunningApp: false,
            ruleIdentifier: "ai.ollama_models",
            safetyExplanation: "Large model weights"
        )

        let catalog = ApplicationMetadataCatalog(homeDirectoryPath: "/Users/testuser")
        var report = ScanAggregationEngine.aggregate(
            candidates: [safeItem, reviewItem],
            appCatalog: catalog,
            scanDurationSeconds: 0.1,
            protectedPathsSkippedCount: 2
        )

        guard let catGroup = report.categories.first else {
            XCTFail("Expected AI category")
            return
        }

        XCTAssertEqual(catGroup.appGroupCount(matching: .all), 2)
        XCTAssertEqual(catGroup.appGroupCount(matching: .safeOnly), 1)
        XCTAssertEqual(catGroup.appGroupCount(matching: .needsReview), 1)
        XCTAssertEqual(catGroup.reviewAppGroupCount, 1)
        XCTAssertEqual(report.selectedReviewItemCount, 0)  // reviewRecommended starts unselected by default

        // Simulate user accidentally selecting all items in the category (including Needs Review)
        for grpIdx in report.categories[0].appGroups.indices {
            for itemIdx in report.categories[0].appGroups[grpIdx].items.indices {
                report.categories[0].appGroups[grpIdx].items[itemIdx].isSelected = true
            }
        }
        XCTAssertEqual(report.selectedReviewItemCount, 1)
        XCTAssertEqual(report.selectedReviewBytes, 600_000_000)

        // Simulate 1-click "Unselect Review" safety action
        for catIdx in report.categories.indices {
            for grpIdx in report.categories[catIdx].appGroups.indices {
                for itemIdx in report.categories[catIdx].appGroups[grpIdx].items.indices {
                    if report.categories[catIdx].appGroups[grpIdx].items[itemIdx].confidence == .reviewRecommended {
                        report.categories[catIdx].appGroups[grpIdx].items[itemIdx].isSelected = false
                    }
                }
            }
        }
        XCTAssertEqual(report.selectedReviewItemCount, 0)
        XCTAssertEqual(report.selectedReviewBytes, 0)
        XCTAssertEqual(report.selectedTotalBytes, 40_000_000)

        for lang in AppLanguage.allCases {
            for filter in ConfidenceFilter.allCases {
                XCTAssertFalse(L10n.confidenceFilterTitle(filter, lang).isEmpty)
            }
            XCTAssertFalse(L10n.unselectReviewButton(lang).isEmpty)
        }
    }

    func testSafeTrashCleanerProgressAndReportPruning() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MacSweepCleanTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let dummyCacheFile = tempRoot.appendingPathComponent("dummy_cache.bin")
        try Data(repeating: 0xAB, count: 4096).write(to: dummyCacheFile)
        let keepCacheFile = tempRoot.appendingPathComponent("keep_cache.bin")
        try Data(repeating: 0xCD, count: 8192).write(to: keepCacheFile)

        let itemToClean = ScanCandidateItem(
            path: dummyCacheFile.path,
            category: .applicationCaches,
            bundleIdentifier: "com.example.clean",
            appDisplayName: "Example Clean App",
            itemName: "Dummy Cache",
            allocatedBytes: 4096,
            fileCount: 1,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: false,
            ruleIdentifier: "test.clean",
            safetyExplanation: "Temporary test cache",
            isSelected: true
        )
        let unselectedItem = ScanCandidateItem(
            path: keepCacheFile.path,
            category: .applicationCaches,
            bundleIdentifier: "com.example.keep",
            appDisplayName: "Example Keep App",
            itemName: "Keep Cache",
            allocatedBytes: 8192,
            fileCount: 1,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: false,
            ruleIdentifier: "test.keep",
            safetyExplanation: "Unselected test cache",
            isSelected: false
        )

        let catalog = ApplicationMetadataCatalog(homeDirectoryPath: "/Users/testuser")
        let initialReport = ScanAggregationEngine.aggregate(
            candidates: [itemToClean, unselectedItem],
            appCatalog: catalog,
            scanDurationSeconds: 0.1,
            protectedPathsSkippedCount: 1
        )
        XCTAssertEqual(initialReport.totalSelectedCount, 1)
        XCTAssertEqual(initialReport.totalCandidateCount, 2)

        let cleaner = SafeTrashCleaner()
        var progressEvents: [(Double, String)] = []
        let summary = cleaner.execute(
            items: [itemToClean, unselectedItem],
            mode: .permanentDelete,
            onProgressUpdate: { fraction, label in
                progressEvents.append((fraction, label))
            }
        )

        XCTAssertEqual(summary.processedItemsCount, 1)
        XCTAssertEqual(summary.bytesReclaimed, 4096)
        XCTAssertTrue(summary.cleanedItemIDs.contains(itemToClean.id))
        XCTAssertFalse(summary.cleanedItemIDs.contains(unselectedItem.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dummyCacheFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: keepCacheFile.path))
        XCTAssertFalse(progressEvents.isEmpty)
        XCTAssertEqual(progressEvents.last?.0, 1.0)

        let prunedReport = initialReport.removingItems(withIDs: summary.cleanedItemIDs)
        XCTAssertEqual(prunedReport.totalCandidateCount, 1)
        XCTAssertEqual(prunedReport.totalSelectedCount, 0)
        XCTAssertEqual(prunedReport.grandTotalBytes, 8192)

        for lang in AppLanguage.allCases {
            XCTAssertFalse(L10n.cleanSelectedButtonTitle(count: 1, formattedBytes: "4 KB", language: lang).isEmpty)
            XCTAssertFalse(L10n.cleaningInProgressTitle(lang).isEmpty)
            XCTAssertFalse(L10n.cleaningInProgressSubtitle(lang).isEmpty)
            XCTAssertFalse(
                L10n.cleanupCompletedStatus(
                    language: lang,
                    movedCount: 1,
                    formattedBytes: "4 KB",
                    skippedCount: 0,
                    errorCount: 0
                ).isEmpty
            )
        }
    }

    func testRunningAppCleanupCoordinatorDetectsOpenAppsAndExcludesSelf() {
        let chromeCacheItem = ScanCandidateItem(
            path: "/Users/testuser/Library/Caches/Google/Chrome/Default/Cache",
            category: .browserCaches,
            bundleIdentifier: "com.google.Chrome",
            appDisplayName: "Google Chrome",
            itemName: "Chrome Network Cache",
            allocatedBytes: 120_000_000,
            fileCount: 410,
            lastModified: Date(),
            confidence: .reviewRecommended,
            isRunningApp: true,
            ruleIdentifier: "browser.chrome.cache",
            safetyExplanation: "Browser cache",
            isSelected: true
        )
        let chromeLogItem = ScanCandidateItem(
            path: "/Users/testuser/Library/Logs/Google/Chrome",
            category: .logsAndDiagnostics,
            bundleIdentifier: "logs.user.com.google.Chrome",
            appDisplayName: "Google Chrome",
            itemName: "Chrome User Logs",
            allocatedBytes: 5_000_000,
            fileCount: 12,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: true,
            ruleIdentifier: "logs.user.chrome",
            safetyExplanation: "User log",
            isSelected: true
        )
        let selfAppItem = ScanCandidateItem(
            path: "/Users/testuser/Library/Caches/com.innotec.MacSweep",
            category: .applicationCaches,
            bundleIdentifier: "com.innotec.MacSweep",
            appDisplayName: "MacSweep",
            itemName: "MacSweep Cache",
            allocatedBytes: 1_024_000,
            fileCount: 4,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: true,
            ruleIdentifier: "cache.user.macsweep",
            safetyExplanation: "Self cache",
            isSelected: true
        )
        let closedAppItem = ScanCandidateItem(
            path: "/Users/testuser/Library/Application Support/Slack/Cache",
            category: .webAndElectronCaches,
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            appDisplayName: "Slack",
            itemName: "Slack Cache",
            allocatedBytes: 80_000_000,
            fileCount: 200,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: false,
            ruleIdentifier: "electron.slack.cache",
            safetyExplanation: "Electron cache",
            isSelected: true
        )

        let simulatedRunningApps: [RunningAppDescriptor] = [
            RunningAppDescriptor(
                bundleIdentifier: "com.google.Chrome",
                localizedName: "Google Chrome",
                bundlePath: "/Applications/Google Chrome.app",
                processIdentifier: 4321,
                isRegularApp: true
            ),
            RunningAppDescriptor(
                bundleIdentifier: "com.innotec.MacSweep",
                localizedName: "MacSweep",
                bundlePath: "/Applications/MacSweep.app",
                processIdentifier: 9999,
                isRegularApp: true
            ),
            RunningAppDescriptor(
                bundleIdentifier: "com.apple.helpd",
                localizedName: "helpd",
                bundlePath: nil,
                processIdentifier: 222,
                isRegularApp: false
            ),
        ]

        let catalog = ApplicationMetadataCatalog(homeDirectoryPath: "/Users/testuser")
        let conflicts = RunningAppCleanupCoordinator.detectConflicts(
            for: [chromeCacheItem, chromeLogItem, selfAppItem, closedAppItem],
            runningApps: simulatedRunningApps,
            appCatalog: catalog
        )

        XCTAssertEqual(conflicts.count, 1, "Only open regular user apps excluding MacSweep itself should be flagged")
        XCTAssertEqual(conflicts.first?.bundleIdentifier, "com.google.Chrome")
        XCTAssertEqual(
            conflicts.first?.affectedItemsCount, 2,
            "Both Chrome cache and Chrome log items should roll up into one conflict entry")
        XCTAssertEqual(conflicts.first?.affectedAllocatedBytes, 125_000_000)

        for lang in AppLanguage.allCases {
            XCTAssertFalse(L10n.runningAppsModalTitle(count: 1, language: lang).isEmpty)
            XCTAssertFalse(L10n.runningAppsModalTitle(count: 3, language: lang).isEmpty)
            XCTAssertFalse(L10n.runningAppsModalSubtitle(lang).isEmpty)
            XCTAssertFalse(L10n.runningAppsQuitAndCleanButton(lang).isEmpty)
            XCTAssertFalse(L10n.runningAppsSkipButton(lang).isEmpty)
            XCTAssertFalse(L10n.runningAppsCleanAnywayButton(lang).isEmpty)
            XCTAssertFalse(L10n.runningAppsCancelButton(lang).isEmpty)
            XCTAssertFalse(L10n.runningAppsClosingProgress(lang).isEmpty)
            XCTAssertFalse(
                L10n.runningAppAffectedSummary(itemsCount: 2, formattedBytes: "125 MB", language: lang).isEmpty)
        }
    }

    func testRunningAppCoordinatorExcludesOfficialBundleIDAndMatchesXcodeAndSimulator() {
        let derivedDataItem = ScanCandidateItem(
            path: "/Users/testuser/Library/Developer/Xcode/DerivedData/MyApp-abc",
            category: .xcodeJunk,
            bundleIdentifier: "com.apple.dt.Xcode.DerivedData",
            appDisplayName: "Xcode DerivedData",
            itemName: "MyApp-abc",
            allocatedBytes: 450_000_000,
            fileCount: 1200,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: true,
            ruleIdentifier: "xcode.derived_data",
            safetyExplanation: "Xcode build artifacts",
            isSelected: true
        )
        let simulatorCacheItem = ScanCandidateItem(
            path: "/Users/testuser/Library/Developer/CoreSimulator/Caches/dyld",
            category: .xcodeJunk,
            bundleIdentifier: "com.apple.CoreSimulator.Caches",
            appDisplayName: "CoreSimulator Caches",
            itemName: "dyld",
            allocatedBytes: 210_000_000,
            fileCount: 85,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: true,
            ruleIdentifier: "xcode.coresimulator_caches",
            safetyExplanation: "Simulator dyld cache",
            isSelected: true
        )
        let officialSelfItem = ScanCandidateItem(
            path: "/Users/testuser/Library/Caches/com.innoteclabs.macsweep",
            category: .applicationCaches,
            bundleIdentifier: "com.innoteclabs.macsweep",
            appDisplayName: "MacSweep",
            itemName: "Self Cache",
            allocatedBytes: 512_000,
            fileCount: 2,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: true,
            ruleIdentifier: "cache.user.self",
            safetyExplanation: "Self cache",
            isSelected: true
        )
        let unselectedSafariItem = ScanCandidateItem(
            path: "/Users/testuser/Library/Caches/com.apple.Safari",
            category: .browserCaches,
            bundleIdentifier: "com.apple.Safari",
            appDisplayName: "Safari",
            itemName: "Safari Cache",
            allocatedBytes: 80_000_000,
            fileCount: 100,
            lastModified: Date(),
            confidence: .reviewRecommended,
            isRunningApp: true,
            ruleIdentifier: "browser.safari",
            safetyExplanation: "Safari cache",
            isSelected: false
        )

        let runningApps: [RunningAppDescriptor] = [
            RunningAppDescriptor(
                bundleIdentifier: "com.innoteclabs.macsweep",
                localizedName: "MacSweep",
                bundlePath: "/Applications/MacSweep.app",
                processIdentifier: 1001,
                isRegularApp: true
            ),
            RunningAppDescriptor(
                bundleIdentifier: "com.apple.dt.Xcode",
                localizedName: "Xcode",
                bundlePath: "/Applications/Xcode.app",
                processIdentifier: 2002,
                isRegularApp: true
            ),
            RunningAppDescriptor(
                bundleIdentifier: "com.apple.iphonesimulator",
                localizedName: "Simulator",
                bundlePath: "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app",
                processIdentifier: 2003,
                isRegularApp: true
            ),
            RunningAppDescriptor(
                bundleIdentifier: "com.apple.Safari",
                localizedName: "Safari",
                bundlePath: "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app",
                processIdentifier: 2004,
                isRegularApp: true
            ),
            RunningAppDescriptor(
                bundleIdentifier: "com.apple.finder",
                localizedName: "Finder",
                bundlePath: "/System/Library/CoreServices/Finder.app",
                processIdentifier: 300,
                isRegularApp: true
            ),
        ]

        let catalog = ApplicationMetadataCatalog(homeDirectoryPath: "/Users/testuser")
        let conflicts = RunningAppCleanupCoordinator.detectConflicts(
            for: [derivedDataItem, simulatorCacheItem, officialSelfItem, unselectedSafariItem],
            runningApps: runningApps,
            appCatalog: catalog
        )

        XCTAssertEqual(
            conflicts.count, 2,
            "Xcode and Simulator should be detected; MacSweep self and unselected Safari must be excluded")
        XCTAssertEqual(conflicts[0].bundleIdentifier, "com.apple.dt.Xcode")
        XCTAssertEqual(conflicts[0].affectedAllocatedBytes, 450_000_000)
        XCTAssertEqual(conflicts[1].bundleIdentifier, "com.apple.iphonesimulator")
        XCTAssertEqual(conflicts[1].affectedAllocatedBytes, 210_000_000)
    }

    func testFullDiskAccessPermissionHelperAndLocalization() throws {
        XCTAssertEqual(
            FullDiskAccessPermissionHelper.systemSettingsDeepLinkURL.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        )

        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MacSweepFDATest-\(UUID().uuidString)")
        let safariDir = tempHome.appendingPathComponent("Library/Safari")
        try FileManager.default.createDirectory(at: safariDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }

        XCTAssertTrue(
            FullDiskAccessPermissionHelper.hasFullDiskAccess(homeDirectoryPath: tempHome.path),
            "Readable Safari directory in sandboxed test home should report Full Disk Access granted"
        )

        for lang in AppLanguage.allCases {
            XCTAssertFalse(L10n.fullDiskAccessGrantedBadge(lang).isEmpty)
            XCTAssertFalse(L10n.fullDiskAccessOptionalPrompt(lang).isEmpty)
            XCTAssertFalse(L10n.fullDiskAccessTooltip(lang).isEmpty)
        }
    }

    func testAppleStoreComplianceManifestsAndEntitlementsAreValidPropertyLists() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let privacyManifestURL = repoRoot.appendingPathComponent("Config/PrivacyInfo.xcprivacy")
        let directEntitlementsURL = repoRoot.appendingPathComponent("Config/MacSweep.Direct.entitlements")
        let appStoreEntitlementsURL = repoRoot.appendingPathComponent("Config/MacSweep.AppStore.entitlements")
        let toLaunchURL = repoRoot.appendingPathComponent("to_launch.md")

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: privacyManifestURL.path), "PrivacyInfo.xcprivacy must exist")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: directEntitlementsURL.path),
            "MacSweep.Direct.entitlements must exist")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: appStoreEntitlementsURL.path),
            "MacSweep.AppStore.entitlements must exist")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: toLaunchURL.path), "to_launch.md manual launch guide must exist")

        let privacyData = try Data(contentsOf: privacyManifestURL)
        let privacyPlist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: privacyData, options: [], format: nil) as? [String: Any]
        )
        XCTAssertEqual(privacyPlist["NSPrivacyTracking"] as? Bool, false, "MacSweep must declare zero tracking")
        let apiTypes = try XCTUnwrap(privacyPlist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let categories = Set(apiTypes.compactMap { $0["NSPrivacyAccessedAPIType"] as? String })
        XCTAssertTrue(categories.contains("NSPrivacyAccessedAPICategoryFileTimestamp"))
        XCTAssertTrue(categories.contains("NSPrivacyAccessedAPICategoryDiskSpace"))

        let directData = try Data(contentsOf: directEntitlementsURL)
        let directPlist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: directData, options: [], format: nil) as? [String: Any]
        )
        XCTAssertEqual(directPlist["com.apple.security.automation.apple-events"] as? Bool, true)

        let storeData = try Data(contentsOf: appStoreEntitlementsURL)
        let storePlist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: storeData, options: [], format: nil) as? [String: Any]
        )
        XCTAssertEqual(storePlist["com.apple.security.app-sandbox"] as? Bool, true)
        XCTAssertEqual(storePlist["com.apple.security.files.user-selected.read-write"] as? Bool, true)
        XCTAssertEqual(storePlist["com.apple.security.files.bookmarks.app-scope"] as? Bool, true)
    }

    func testSafetyGuardEngineBlocksSymlinkEscapeToProtectedDirectory() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MacSweepSymlinkTest-\(UUID().uuidString)")
        let cacheDir = tempRoot.appendingPathComponent("Library/Caches/com.example.app")
        let documentsDir = tempRoot.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documentsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let symlinkURL = cacheDir.appendingPathComponent("EscapedDocsLink")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: documentsDir)

        let engine = SafetyGuardEngine(homeDirectoryPath: tempRoot.path)
        let evaluation = engine.evaluate(
            path: symlinkURL.path,
            category: .applicationCaches,
            bundleIdentifier: "com.example.app",
            displayName: "Example App",
            defaultReason: "Test symlink escape"
        )
        XCTAssertFalse(evaluation.isAllowed)
        XCTAssertEqual(
            evaluation.confidence,
            .blocked,
            "Symlinks inside Caches pointing to ~/Documents must be blocked by canonical realpath safety layer"
        )
    }

    func testSafeTrashCleanerBlocksProtectedPathsAndSupportsDryRunZeroDeletions() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MacSweepGuardCleanTest-\(UUID().uuidString)")
        let cacheDir = tempRoot.appendingPathComponent("Library/Caches/com.example.app")
        let docsDir = tempRoot.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let safeFile = cacheDir.appendingPathComponent("regenerable.cache")
        let protectedDocFile = docsDir.appendingPathComponent("secret.pdf")
        try Data(repeating: 0x11, count: 2048).write(to: safeFile)
        try Data(repeating: 0x22, count: 4096).write(to: protectedDocFile)

        let safeCandidate = ScanCandidateItem(
            path: safeFile.path,
            category: .applicationCaches,
            bundleIdentifier: "com.example.app",
            appDisplayName: "Example App",
            itemName: "regenerable.cache",
            allocatedBytes: 2048,
            fileCount: 1,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: false,
            ruleIdentifier: "test.safe",
            safetyExplanation: "Safe cache",
            isSelected: true
        )
        let forbiddenCandidate = ScanCandidateItem(
            path: protectedDocFile.path,
            category: .applicationCaches,
            bundleIdentifier: "com.example.app",
            appDisplayName: "Example App",
            itemName: "secret.pdf",
            allocatedBytes: 4096,
            fileCount: 1,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: false,
            ruleIdentifier: "test.forbidden",
            safetyExplanation: "Tampered path inside Documents",
            isSelected: true
        )

        let guardEngine = SafetyGuardEngine(homeDirectoryPath: tempRoot.path)
        let cleaner = SafeTrashCleaner(safetyEngine: guardEngine)

        // 1. Dry-run must never delete any file on disk
        let dryRunSummary = cleaner.execute(items: [safeCandidate, forbiddenCandidate], mode: .dryRunPreview)
        XCTAssertEqual(dryRunSummary.processedItemsCount, 1)
        XCTAssertEqual(dryRunSummary.skippedProtectedCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: safeFile.path), "Dry-run must not delete safe file")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: protectedDocFile.path), "Dry-run must not delete protected file")

        // 2. Permanent delete must remove the safe cache and hard-block the Documents file
        let deleteSummary = cleaner.execute(items: [safeCandidate, forbiddenCandidate], mode: .permanentDelete)
        XCTAssertEqual(deleteSummary.processedItemsCount, 1)
        XCTAssertEqual(deleteSummary.skippedProtectedCount, 1)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: safeFile.path), "Safe cache file should be permanently removed")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: protectedDocFile.path),
            "Protected ~/Documents file must remain untouched")
    }

    func testByteFormatterAndHomePathAbbreviation() {
        XCTAssertTrue(
            ByteFormatter.string(from: 0).lowercased().contains("zero") || ByteFormatter.string(from: 0).contains("0"))
        XCTAssertFalse(ByteFormatter.string(from: 1_048_576).isEmpty)
        XCTAssertFalse(ByteFormatter.string(from: 1_073_741_824).isEmpty)

        let abbreviated = L10n.abbreviateHomePath("/Users/anyuser/Library/Caches/com.example.app")
        XCTAssertEqual(abbreviated, "~/Library/Caches/com.example.app")
        XCTAssertEqual(L10n.abbreviateHomePath("/Library/Caches"), "/Library/Caches")
    }

    func testCleanupCategoryAndScanScopeExhaustiveMetadataAndLocalization() {
        for lang in AppLanguage.allCases {
            XCTAssertFalse(lang.displayName.isEmpty)
            XCTAssertFalse(lang.shortLabel.isEmpty)

            for scope in ScanScope.allCases {
                XCTAssertFalse(scope.title(in: lang).isEmpty)
                XCTAssertFalse(scope.subtitle.isEmpty)
                XCTAssertFalse(scope.shortDescription(in: lang).isEmpty)
                XCTAssertFalse(scope.systemSymbolName.isEmpty)
                XCTAssertFalse(scope.includedCategories.isEmpty)
            }

            for category in CleanupCategory.allCases {
                XCTAssertFalse(category.title(in: lang).isEmpty)
                XCTAssertFalse(category.subtitle(in: lang).isEmpty)
                XCTAssertFalse(category.systemSymbolName.isEmpty)
                XCTAssertTrue(category.scope.includedCategories.contains(category))
            }
        }
    }

    func testLogsAndDiagnosticsExcludesRootLogsAndCleansUserLogs() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MacSweepLogsTest-\(UUID().uuidString)")
        let userLogsDir = tempRoot.appendingPathComponent("Library/Logs/ExampleApp")
        let diagReportsDir = tempRoot.appendingPathComponent("Library/Logs/DiagnosticReports")
        try FileManager.default.createDirectory(at: userLogsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: diagReportsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let oldDate = Date().addingTimeInterval(-3600)
        let logFile = userLogsDir.appendingPathComponent("app.log")
        let crashFile = diagReportsDir.appendingPathComponent("ExampleApp-2026.ips")
        try Data(repeating: 0x41, count: 65_536).write(to: logFile)
        try Data(repeating: 0x42, count: 65_536).write(to: crashFile)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: logFile.path)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: crashFile.path)

        let engine = SafetyGuardEngine(homeDirectoryPath: tempRoot.path)

        // Root-owned system log directories must be hard-blocked and non-deletable
        XCTAssertFalse(SafetyGuardEngine.isPathUserDeletable("/private/var/log"))
        XCTAssertTrue(SafetyGuardEngine.isPathUserDeletable(logFile.path))

        for rootLogPath in ["/private/var/log/install.log", "/Library/Logs/CrashReporter", "/var/log/system.log"] {
            let verdict = engine.evaluate(
                path: rootLogPath,
                category: .logsAndDiagnostics,
                bundleIdentifier: "com.apple.system",
                displayName: "System Log",
                defaultReason: "Test"
            )
            XCTAssertFalse(verdict.isAllowed, "Root system log path must be blocked: \(rootLogPath)")
            XCTAssertEqual(verdict.confidence, .blocked)
        }

        let catalog = ApplicationMetadataCatalog(homeDirectoryPath: tempRoot.path)
        let scanner = LogsAndDiagnosticsSubscanner()
        let result = scanner.scan(safetyEngine: engine, appCatalog: catalog)

        // Verify no candidate comes from /private/var/log or /Library/Logs
        XCTAssertFalse(
            result.candidates.contains { $0.path.hasPrefix("/private/var/log") || $0.path.hasPrefix("/Library/Logs") })
        XCTAssertEqual(result.candidates.count, 2)

        // Verify SafeTrashCleaner permanently deletes all discovered user log items
        let cleaner = SafeTrashCleaner(safetyEngine: engine)
        let summary = cleaner.execute(items: result.candidates, mode: .permanentDelete)
        XCTAssertEqual(summary.processedItemsCount, 2)
        XCTAssertTrue(summary.errors.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: userLogsDir.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: crashFile.path))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: diagReportsDir.path),
            "DiagnosticReports root folder should be preserved")
    }

    func testUniversalDeletabilityCheckExcludesImmutableAndReadOnlyItemsAcrossAllLayers() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MacSweepUniversalDeletable-\(UUID().uuidString)")
        let cachesDir = tempRoot.appendingPathComponent("Library/Caches")
        let deletableAppDir = cachesDir.appendingPathComponent("com.example.deletable")
        let immutableFile = cachesDir.appendingPathComponent("com.example.lockedfile")
        let readOnlyParentDir = cachesDir.appendingPathComponent("com.example.readonlyparent")
        let childInsideReadOnly = readOnlyParentDir.appendingPathComponent("locked_child.cache")

        try FileManager.default.createDirectory(at: deletableAppDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: readOnlyParentDir, withIntermediateDirectories: true)

        let normalFile = deletableAppDir.appendingPathComponent("normal.cache")
        try Data(repeating: 0xAA, count: 32_768).write(to: normalFile)
        try Data(repeating: 0xBB, count: 32_768).write(to: immutableFile)
        try Data(repeating: 0xCC, count: 32_768).write(to: childInsideReadOnly)

        // Lock `immutableFile` with UF_IMMUTABLE and remove write permission on `readOnlyParentDir`
        _ = chflags(immutableFile.path, UInt32(UF_IMMUTABLE))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnlyParentDir.path)

        defer {
            _ = chflags(immutableFile.path, 0)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnlyParentDir.path)
            try? FileManager.default.removeItem(at: tempRoot)
        }

        // 1. SafetyGuardEngine.isPathUserDeletable must reject immutable files, read-only directories, and children inside read-only parents
        XCTAssertTrue(SafetyGuardEngine.isPathUserDeletable(deletableAppDir.path))
        XCTAssertFalse(
            SafetyGuardEngine.isPathUserDeletable(immutableFile.path),
            "UF_IMMUTABLE file must be rejected as non-deletable")
        XCTAssertFalse(
            SafetyGuardEngine.isPathUserDeletable(readOnlyParentDir.path),
            "0555 directory must be rejected as non-deletable")
        XCTAssertFalse(
            SafetyGuardEngine.isPathUserDeletable(childInsideReadOnly.path),
            "Child inside 0555 parent directory must be rejected as non-deletable")

        // 2. DiskAllocatedSizeCalculator.measure must return 0 bytes for non-deletable paths
        XCTAssertGreaterThan(DiskAllocatedSizeCalculator.measure(path: deletableAppDir.path).allocatedBytes, 0)
        XCTAssertEqual(DiskAllocatedSizeCalculator.measure(path: immutableFile.path).allocatedBytes, 0)
        XCTAssertEqual(DiskAllocatedSizeCalculator.measure(path: readOnlyParentDir.path).allocatedBytes, 0)
        XCTAssertEqual(DiskAllocatedSizeCalculator.measure(path: childInsideReadOnly.path).allocatedBytes, 0)

        // 3. ApplicationCacheSubscanner must only list the deletable cache and skip undeletable siblings
        let engine = SafetyGuardEngine(homeDirectoryPath: tempRoot.path)
        let catalog = ApplicationMetadataCatalog(homeDirectoryPath: tempRoot.path)
        let scanResult = ApplicationCacheSubscanner().scan(safetyEngine: engine, appCatalog: catalog)
        XCTAssertEqual(scanResult.candidates.count, 1)
        XCTAssertEqual(scanResult.candidates.first?.path, deletableAppDir.path)

        // 4. ScanAggregationEngine must also act as a final gate and drop any synthetic undeletable candidate
        let syntheticUndeletable = ScanCandidateItem(
            path: immutableFile.path,
            category: .applicationCaches,
            bundleIdentifier: "com.example.lockedfile",
            appDisplayName: "Locked File",
            itemName: "Locked File",
            allocatedBytes: 32_768,
            fileCount: 1,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: false,
            ruleIdentifier: "test.locked",
            safetyExplanation: "Synthetic locked item"
        )
        let report = ScanAggregationEngine.aggregate(
            candidates: scanResult.candidates + [syntheticUndeletable],
            appCatalog: catalog,
            scanDurationSeconds: 0.05,
            protectedPathsSkippedCount: scanResult.skippedProtectedCount
        )
        let allListedPaths = report.categories.flatMap(\.appGroups).flatMap(\.items).map(\.path)
        XCTAssertEqual(
            allListedPaths, [deletableAppDir.path], "Undeletable items must never appear in the aggregated ScanReport")
    }

    func testScanOrchestratorSubscannerWeightsAndMonotonicProgress() {
        let orchestrator = ScanOrchestrator()
        XCTAssertEqual(orchestrator.subscanners.count, 7)

        var totalWeight = 0.0
        for scanner in orchestrator.subscanners {
            let explicitWeight = ScanProgressTracker.weight(for: scanner.identifier)
            XCTAssertNotNil(
                explicitWeight,
                "Subscanner '\(scanner.identifier)' must have an explicit weight in ScanProgressTracker.weight(for:)"
            )
            XCTAssertEqual(scanner.progressWeight, explicitWeight ?? 0.0, accuracy: 0.0001)
            totalWeight += scanner.progressWeight
        }
        XCTAssertEqual(totalWeight, 1.0, accuracy: 0.0001, "All 7 default subscanner weights must sum to 1.0")

        let tracker = ScanProgressTracker(subscanners: orchestrator.subscanners)
        var lastFraction = tracker.recordMilestone(0.04)
        XCTAssertEqual(lastFraction, 0.04, accuracy: 0.0001)

        let startFraction = tracker.markSubscannerStarted()
        XCTAssertGreaterThanOrEqual(startFraction, lastFraction)
        lastFraction = startFraction

        for scanner in orchestrator.subscanners {
            let state = tracker.markSubscannerCompleted(identifier: scanner.identifier)
            XCTAssertGreaterThanOrEqual(state.fraction, lastFraction, "Progress must be monotonically non-decreasing")
            XCTAssertLessThanOrEqual(
                state.fraction, 0.9201, "Subscanner completion phase is capped at 0.92 before aggregation")
            lastFraction = state.fraction
        }

        let finalFraction = tracker.recordMilestone(1.0)
        XCTAssertEqual(finalFraction, 1.0, accuracy: 0.0001)
    }

    func testRuleKnowledgeBaseSafetyInvariantsAndAIModelConfidence() {
        let rules = RuleKnowledgeBase.shared
        let allRecipes = rules.developerToolchainRecipes
        XCTAssertFalse(allRecipes.isEmpty)

        // 1. All recipe IDs must be unique and have non-empty explanations
        let uniqueIDs = Set(allRecipes.map(\.id))
        XCTAssertEqual(uniqueIDs.count, allRecipes.count, "Every ToolchainCacheRecipe must have a unique ID")
        for recipe in allRecipes {
            XCTAssertFalse(recipe.displayName.isEmpty)
            XCTAssertFalse(recipe.bundleIdentifier.isEmpty)
            XCTAssertFalse(recipe.relativePathFromHome.isEmpty)
            XCTAssertFalse(recipe.explanation.isEmpty)
            XCTAssertNotEqual(
                recipe.confidence, .blocked, "Catalog recipes should be safeAutoSelect or reviewRecommended")
        }

        // 2. Multi-GB local AI model weight stores must require manual review (.reviewRecommended)
        let ollamaRecipe = allRecipes.first { $0.id == "ai.ollama_models" }
        let hfRecipe = allRecipes.first { $0.id == "ai.huggingface_cache" }
        XCTAssertEqual(
            ollamaRecipe?.confidence, .reviewRecommended, "Ollama LLM weights must never be auto-selected by default")
        XCTAssertEqual(
            hfRecipe?.confidence, .reviewRecommended,
            "Hugging Face Hub model weights must never be auto-selected by default")

        // 3. No recipe path may target a protected home-relative root (e.g. Documents, Desktop, .ssh, .aws, Keychains)
        let exclusionTree = ExclusionPrefixTree(
            excludedPaths: rules.protectedHomeRelativeRoots.map { "/Users/testuser/\($0)" }
        )
        for recipe in allRecipes {
            let candidatePath = "/Users/testuser/\(recipe.relativePathFromHome)"
            XCTAssertFalse(
                exclusionTree.isPathOrAncestorExcluded(candidatePath),
                "Recipe '\(recipe.id)' (\(candidatePath)) must never overlap a protected user root"
            )
        }
    }

    func testDiskAllocatedSizeCalculatorHardLinkDeduplicationAndSymlinkSkipping() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MacSweepDiskCalc-\(UUID().uuidString)")
        let measuredDir = tempRoot.appendingPathComponent("MeasuredCache")
        let externalDir = tempRoot.appendingPathComponent("ExternalTarget")
        let protectedSubdir = measuredDir.appendingPathComponent("CloudKit")
        try FileManager.default.createDirectory(at: measuredDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: protectedSubdir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        // 1. Create a 64 KB primary file and a hard link (`link()`) to the exact same inode
        let originalFile = measuredDir.appendingPathComponent("shard_primary.bin")
        let hardLinkedFile = measuredDir.appendingPathComponent("shard_hardlink.bin")
        try Data(repeating: 0x5A, count: 65_536).write(to: originalFile)
        XCTAssertEqual(link(originalFile.path, hardLinkedFile.path), 0, "POSIX hard link creation should succeed")

        let singleMetrics = DiskAllocatedSizeCalculator.measure(path: originalFile.path)
        XCTAssertGreaterThan(singleMetrics.allocatedBytes, 0)

        // 2. Create a large 256 KB file outside `measuredDir` and symlink to it from inside `measuredDir`
        let externalLargeFile = externalDir.appendingPathComponent("outside.bin")
        try Data(repeating: 0x7F, count: 262_144).write(to: externalLargeFile)
        let symlinkInsideMeasured = measuredDir.appendingPathComponent("symlink_to_outside.bin")
        try FileManager.default.createSymbolicLink(at: symlinkInsideMeasured, withDestinationURL: externalLargeFile)

        // 3. Create a 128 KB file inside the protected `CloudKit` subdirectory
        let protectedFile = protectedSubdir.appendingPathComponent("cloudkit_record.db")
        try Data(repeating: 0x33, count: 131_072).write(to: protectedFile)

        // Measure `measuredDir` with `protectedComponentNames: ["CloudKit"]`
        let dirMetrics = DiskAllocatedSizeCalculator.measure(
            path: measuredDir.path,
            protectedComponentNames: ["CloudKit"]
        )

        // Hard-linked inode must be counted only once (`fileCount == 1`), symlink target must not be traversed,
        // and protected `CloudKit` child must be skipped.
        XCTAssertEqual(
            dirMetrics.fileCount, 1, "Hard-linked inode must be deduplicated and symlinks/protected dirs skipped")
        XCTAssertEqual(
            dirMetrics.allocatedBytes, singleMetrics.allocatedBytes,
            "Allocated bytes must match a single copy of the hard-linked file")
    }

    func testSafeTrashCleanerBlocksTOCTOUSymlinkSwapAndCleansPartialDirectories() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MacSweepTOCTOU-\(UUID().uuidString)")
        let cachesRoot = tempRoot.appendingPathComponent("Library/Caches")
        let appCacheDir = cachesRoot.appendingPathComponent("com.example.swapped")
        let documentsDir = tempRoot.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: appCacheDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documentsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let secretDoc = documentsDir.appendingPathComponent("tax_return.pdf")
        try Data(repeating: 0x99, count: 16_384).write(to: secretDoc)

        // Candidate was scanned when `appCacheDir` was an ordinary cache directory
        let swappedCandidate = ScanCandidateItem(
            path: appCacheDir.path,
            category: .applicationCaches,
            bundleIdentifier: "com.example.swapped",
            appDisplayName: "Swapped App",
            itemName: "Swapped Cache",
            allocatedBytes: 16_384,
            fileCount: 1,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: false,
            ruleIdentifier: "test.toctou",
            safetyExplanation: "Cache folder",
            isSelected: true
        )

        // Simulate TOCTOU symlink swap before cleanup execution: replace `appCacheDir` with a symlink to `~/Documents`
        try FileManager.default.removeItem(at: appCacheDir)
        try FileManager.default.createSymbolicLink(at: appCacheDir, withDestinationURL: documentsDir)

        let engine = SafetyGuardEngine(homeDirectoryPath: tempRoot.path)
        let cleaner = SafeTrashCleaner(safetyEngine: engine)
        let toctouSummary = cleaner.execute(items: [swappedCandidate], mode: .permanentDelete)

        XCTAssertEqual(
            toctouSummary.processedItemsCount, 0,
            "TOCTOU symlink pointing to ~/Documents must be blocked at deletion time")
        XCTAssertEqual(toctouSummary.skippedProtectedCount, 1)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: secretDoc.path),
            "Protected file inside ~/Documents must remain intact")

        // Also test selective child deletion when a parent directory has an excluded descendant (`Library/Caches/CloudKit`)
        try FileManager.default.removeItem(at: appCacheDir)
        let cloudKitDir = cachesRoot.appendingPathComponent("CloudKit")
        let safeSiblingDir = cachesRoot.appendingPathComponent("com.example.safe")
        try FileManager.default.createDirectory(at: cloudKitDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: safeSiblingDir, withIntermediateDirectories: true)
        let cloudKitFile = cloudKitDir.appendingPathComponent("sync.db")
        let safeSiblingFile = safeSiblingDir.appendingPathComponent("http.cache")
        try Data(repeating: 0x11, count: 4096).write(to: cloudKitFile)
        try Data(repeating: 0x22, count: 4096).write(to: safeSiblingFile)

        let parentCachesCandidate = ScanCandidateItem(
            path: cachesRoot.path,
            category: .applicationCaches,
            bundleIdentifier: "com.example.parent",
            appDisplayName: "Parent Caches",
            itemName: "Caches Root",
            allocatedBytes: 4096,
            fileCount: 1,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: false,
            ruleIdentifier: "test.partial",
            safetyExplanation: "Parent directory with protected child",
            isSelected: true
        )

        let partialSummary = cleaner.execute(items: [parentCachesCandidate], mode: .permanentDelete)
        XCTAssertEqual(partialSummary.processedItemsCount, 1)
        XCTAssertGreaterThanOrEqual(partialSummary.skippedProtectedCount, 1, "Protected CloudKit child must be skipped")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: cloudKitFile.path), "Protected CloudKit database must be preserved")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: safeSiblingDir.path), "Safe sibling cache must be removed")
    }

    func testEndToEndScanOrchestratorOnSandboxedMockHomeDirectory() async throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MacSweepE2EHome-\(UUID().uuidString)")
        let appCacheDir = tempHome.appendingPathComponent("Library/Caches/com.example.editor")
        let cloudKitCacheDir = tempHome.appendingPathComponent("Library/Caches/CloudKit")
        let prefsDir = tempHome.appendingPathComponent("Library/Preferences")
        let downloadsDir = tempHome.appendingPathComponent("Downloads")
        let documentsDir = tempHome.appendingPathComponent("Documents")

        for dir in [appCacheDir, cloudKitCacheDir, prefsDir, downloadsDir, documentsDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: tempHome) }

        // 1. Safe application cache (64 KB)
        try Data(repeating: 0xAB, count: 65_536).write(to: appCacheDir.appendingPathComponent("index.cache"))
        // 2. Protected CloudKit cache (must be skipped)
        try Data(repeating: 0xCD, count: 65_536).write(to: cloudKitCacheDir.appendingPathComponent("Protected.db"))
        // 3. Corrupted 0-byte preference plist (must be detected)
        try Data().write(to: prefsDir.appendingPathComponent("com.example.broken.plist"))
        // 4. Aged .dmg installer (45 days old -> Review Recommended)
        let oldDmg = downloadsDir.appendingPathComponent("LegacyInstaller.dmg")
        try Data(repeating: 0xEF, count: 65_536).write(to: oldDmg)
        let fortyFiveDaysAgo = Date().addingTimeInterval(-45.0 * 86_400.0)
        try FileManager.default.setAttributes([.modificationDate: fortyFiveDaysAgo], ofItemAtPath: oldDmg.path)
        // 5. Protected personal document in ~/Documents (must never be scanned or touched)
        try Data(repeating: 0x12, count: 65_536).write(to: documentsDir.appendingPathComponent("PrivateNotes.md"))

        final class FractionRecorder: @unchecked Sendable {
            private let lock = NSLock()
            private var values: [Double] = []
            func append(_ value: Double) {
                lock.lock()
                values.append(value)
                lock.unlock()
            }
            func snapshot() -> [Double] {
                lock.lock()
                defer { lock.unlock() }
                return values
            }
        }

        let orchestrator = ScanOrchestrator(homeDirectoryPath: tempHome.path)
        let recorder = FractionRecorder()

        let report = await orchestrator.runScan(
            scopes: Set(ScanScope.allCases),
            onProgressUpdate: { fraction, _ in
                recorder.append(fraction)
            }
        )

        let recordedFractions = recorder.snapshot()

        XCTAssertFalse(recordedFractions.isEmpty)
        XCTAssertEqual(recordedFractions.last ?? 0.0, 1.0, accuracy: 0.0001)
        for idx in 1..<recordedFractions.count {
            XCTAssertGreaterThanOrEqual(
                recordedFractions[idx],
                recordedFractions[idx - 1],
                "ScanOrchestrator progress callbacks must be strictly non-decreasing"
            )
        }

        let discoveredPaths = Set(report.categories.flatMap(\.appGroups).flatMap(\.items).map(\.path))
        XCTAssertTrue(discoveredPaths.contains(appCacheDir.path), "Safe app cache should be discovered")
        XCTAssertTrue(discoveredPaths.contains(oldDmg.path), "Aged .dmg installer should be discovered")
        XCTAssertFalse(
            discoveredPaths.contains { $0.contains("CloudKit") || $0.contains("Documents") },
            "Protected CloudKit and Documents paths must never appear in ScanReport"
        )
    }

    // MARK: - 100% Full-Repository Coverage Suite

    func testScanOrchestratorCustomSubscannerDefaultWeightAndUnknownIdentifier() {
        struct CustomSubscanner: CleanupSubscanner {
            let identifier = "custom.unknown_scanner"
            let displayName = "Custom Scanner"
            func scan(safetyEngine: SafetyGuardEngine, appCatalog: ApplicationMetadataCatalog) -> SubscannerResult {
                SubscannerResult(candidates: [], skippedProtectedCount: 0)
            }
        }

        let custom = CustomSubscanner()
        XCTAssertNil(ScanProgressTracker.weight(for: custom.identifier))
        XCTAssertEqual(custom.progressWeight, 0.14, accuracy: 0.0001)

        let tracker = ScanProgressTracker(subscanners: [custom])
        let unknownDone = tracker.markSubscannerCompleted(identifier: "non.existent.id")
        XCTAssertGreaterThanOrEqual(unknownDone.fraction, 0.0)
        let customDone = tracker.markSubscannerCompleted(identifier: custom.identifier)
        XCTAssertEqual(customDone.fraction, 0.92, accuracy: 0.0001)
    }

    func testScanAggregationEngineDeduplicationAndRunningProcessDetection() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MacSweepAggTest-\(UUID().uuidString)")
        let cacheDir = tempRoot.appendingPathComponent("Library/Caches/com.google.Chrome")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let cacheFile = cacheDir.appendingPathComponent("data_0")
        try Data(repeating: 0x33, count: 8192).write(to: cacheFile)

        let smallerCandidate = ScanCandidateItem(
            path: cacheFile.path,
            category: .applicationCaches,
            bundleIdentifier: "com.google.Chrome",
            appDisplayName: "Google Chrome",
            itemName: "data_0 (small)",
            allocatedBytes: 4096,
            fileCount: 1,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: false,
            ruleIdentifier: "test.small",
            safetyExplanation: "Small duplicate"
        )
        let largerCandidate = ScanCandidateItem(
            path: cacheFile.path,
            category: .applicationCaches,
            bundleIdentifier: "com.google.Chrome",
            appDisplayName: "",
            itemName: "data_0 (large)",
            allocatedBytes: 8192,
            fileCount: 1,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: true,
            ruleIdentifier: "test.large",
            safetyExplanation: "Large duplicate"
        )
        let blockedCandidate = ScanCandidateItem(
            path: cacheFile.path,
            category: .applicationCaches,
            bundleIdentifier: "com.google.Chrome",
            appDisplayName: "Google Chrome",
            itemName: "blocked",
            allocatedBytes: 8192,
            fileCount: 1,
            lastModified: Date(),
            confidence: .blocked,
            isRunningApp: false,
            ruleIdentifier: "test.blocked",
            safetyExplanation: "Blocked"
        )
        let zeroByteCandidate = ScanCandidateItem(
            path: cacheFile.path,
            category: .applicationCaches,
            bundleIdentifier: "com.google.Chrome",
            appDisplayName: "Google Chrome",
            itemName: "zero",
            allocatedBytes: 0,
            fileCount: 1,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: false,
            ruleIdentifier: "test.zero",
            safetyExplanation: "Zero"
        )

        let catalog = ApplicationMetadataCatalog(homeDirectoryPath: tempRoot.path)
        let report1 = ScanAggregationEngine.aggregate(
            candidates: [smallerCandidate, largerCandidate, blockedCandidate, zeroByteCandidate],
            appCatalog: catalog,
            scanDurationSeconds: 0.1,
            protectedPathsSkippedCount: 2
        )
        XCTAssertEqual(report1.grandTotalBytes, 8192)
        XCTAssertEqual(report1.categories.first?.appGroups.first?.isRunning, true)

        // Reverse order: larger first, then smaller (ensures existing.allocatedBytes >= item.allocatedBytes branch runs)
        let report2 = ScanAggregationEngine.aggregate(
            candidates: [largerCandidate, smallerCandidate],
            appCatalog: catalog,
            scanDurationSeconds: 0.1,
            protectedPathsSkippedCount: 0
        )
        XCTAssertEqual(report2.grandTotalBytes, 8192)
    }

    func testApplicationMetadataCatalogAliasesAndInstalledAppScanning() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MacSweepAppCatalog-\(UUID().uuidString)")
        let userAppsDir = tempHome.appendingPathComponent("Applications")
        let demoAppContents = userAppsDir.appendingPathComponent("DemoApp.app/Contents")
        let fallbackAppContents = userAppsDir.appendingPathComponent("FallbackApp.app/Contents")
        try FileManager.default.createDirectory(at: demoAppContents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fallbackAppContents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let demoPlist: [String: Any] = [
            "CFBundleIdentifier": "com.unknownvendor.DemoApp",
            "CFBundleDisplayName": "Super Demo App",
        ]
        let demoPlistData = try PropertyListSerialization.data(fromPropertyList: demoPlist, format: .xml, options: 0)
        try demoPlistData.write(to: demoAppContents.appendingPathComponent("Info.plist"))

        // FallbackApp has no CFBundleDisplayName or CFBundleName so it falls back to deletingPathExtension
        let fallbackPlist: [String: Any] = [
            "CFBundleIdentifier": "com.unknownvendor.FallbackApp"
        ]
        let fallbackPlistData = try PropertyListSerialization.data(
            fromPropertyList: fallbackPlist, format: .xml, options: 0)
        try fallbackPlistData.write(to: fallbackAppContents.appendingPathComponent("Info.plist"))

        // EmptyBundleID.app has Info.plist without CFBundleIdentifier, and NoPlist.app has no Info.plist
        let emptyIDAppContents = userAppsDir.appendingPathComponent("EmptyBundleID.app/Contents")
        let noPlistAppDir = userAppsDir.appendingPathComponent("NoPlist.app")
        try FileManager.default.createDirectory(at: emptyIDAppContents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: noPlistAppDir, withIntermediateDirectories: true)
        let emptyIDPlist: [String: Any] = ["CFBundleName": "EmptyID"]
        let emptyIDPlistData = try PropertyListSerialization.data(
            fromPropertyList: emptyIDPlist, format: .xml, options: 0)
        try emptyIDPlistData.write(to: emptyIDAppContents.appendingPathComponent("Info.plist"))

        let catalog = ApplicationMetadataCatalog(homeDirectoryPath: tempHome.path)

        // 1. Direct bundle ID match from scanned ~/Applications
        let demoMeta = catalog.resolve(folderOrBundleIdentifier: "com.unknownvendor.DemoApp")
        XCTAssertEqual(demoMeta.displayName, "Super Demo App")
        XCTAssertNotNil(demoMeta.bundlePath)

        // 2. Known alias match (e.g. "rave" -> Rave)
        let raveMeta = catalog.resolve(folderOrBundleIdentifier: "rave")
        XCTAssertEqual(raveMeta.displayName, "Rave")

        // 3. 3+ component bundle identifier heuristic matching installed app by last component
        let heuristicMeta = catalog.resolve(folderOrBundleIdentifier: "org.other.FallbackApp")
        XCTAssertEqual(heuristicMeta.displayName, "FallbackApp")

        // 4. 3+ component bundle identifier with no installed app match (humanizeIdentifier fallback)
        let humanizedMeta = catalog.resolve(folderOrBundleIdentifier: "com.somecompany.my_cool-tool")
        XCTAssertFalse(humanizedMeta.displayName.isEmpty)
    }

    func testExclusionPrefixTreeEdgeCases() {
        let tree = ExclusionPrefixTree(excludedPaths: ["/Users/testuser/Documents", "/"])
        XCTAssertTrue(tree.isPathOrAncestorExcluded("/"))
        XCTAssertTrue(tree.hasExcludedDescendant("/Users/testuser"))
        XCTAssertTrue(tree.hasExcludedDescendant("/Users/testuser/Documents"))

        let specificTree = ExclusionPrefixTree(excludedPaths: ["/Users/testuser/Documents/Secret"])
        XCTAssertTrue(specificTree.isPathOrAncestorExcluded("/"))
        XCTAssertTrue(specificTree.hasExcludedDescendant("/"))
        XCTAssertTrue(specificTree.hasExcludedDescendant("/Users/testuser/Documents"))
        XCTAssertTrue(specificTree.hasExcludedDescendant("/Users/testuser/Documents/Secret"))
        XCTAssertFalse(specificTree.hasExcludedDescendant("/Users/testuser/Downloads"))
    }

    func testDiskAllocatedSizeCalculatorAllBranches() throws {
        // 1. Non-existent path
        let missingMetrics = DiskAllocatedSizeCalculator.measure(
            path: "/nonexistent/macsweep/path/\(UUID().uuidString)")
        XCTAssertEqual(missingMetrics.allocatedBytes, 0)

        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MacSweepCalcBranches-\(UUID().uuidString)")
        let dirA = tempRoot.appendingPathComponent("DirA")
        let childLockedDir = dirA.appendingPathComponent("LockedSubdir")
        let childNoPermDir = dirA.appendingPathComponent("NoPermSubdir")
        try FileManager.default.createDirectory(at: childLockedDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: childNoPermDir, withIntermediateDirectories: true)

        let normalFile = dirA.appendingPathComponent("normal.dat")
        let lockedFile = dirA.appendingPathComponent("locked.dat")
        let symlinkRoot = tempRoot.appendingPathComponent("RootSymlink")
        let fifoPath = dirA.appendingPathComponent("test.fifo")

        try Data(repeating: 0xAA, count: 16_384).write(to: normalFile)
        try Data(repeating: 0xBB, count: 16_384).write(to: lockedFile)
        try FileManager.default.createSymbolicLink(at: symlinkRoot, withDestinationURL: normalFile)
        _ = mkfifo(fifoPath.path, 0o644)

        // Set future modification date on normalFile so fileModTime > maxModTime triggers
        let futureDate = Date().addingTimeInterval(3600)
        try FileManager.default.setAttributes([.modificationDate: futureDate], ofItemAtPath: normalFile.path)

        // Lock childLockedDir and lockedFile with UF_IMMUTABLE, and remove permissions on childNoPermDir
        _ = chflags(childLockedDir.path, UInt32(UF_IMMUTABLE))
        _ = chflags(lockedFile.path, UInt32(UF_IMMUTABLE))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: childNoPermDir.path)

        defer {
            _ = chflags(childLockedDir.path, 0)
            _ = chflags(lockedFile.path, 0)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: childNoPermDir.path)
            try? FileManager.default.removeItem(at: tempRoot)
        }

        // 2. Root symlink and root FIFO measurement return 0
        XCTAssertEqual(DiskAllocatedSizeCalculator.measure(path: symlinkRoot.path).allocatedBytes, 0)
        XCTAssertEqual(DiskAllocatedSizeCalculator.measure(path: fifoPath.path).allocatedBytes, 0)

        // 3. Measure directory containing normal file, locked file, FIFO, locked subdir, and 000 subdir
        let metrics = DiskAllocatedSizeCalculator.measure(path: dirA.path)
        XCTAssertEqual(
            metrics.fileCount, 1,
            "Only normalFile should be counted; locked file, FIFO, and locked/unreadable subdirs must be skipped")
        XCTAssertGreaterThan(metrics.allocatedBytes, 0)

        // 4. Measure directory when child files have mismatched effectiveUID (simulating root-owned child inside user dir)
        // Note: top-level isPathUserDeletable uses default geteuid(), while child loop compares against passed effectiveUID
        let uidMismatchMetrics = DiskAllocatedSizeCalculator.measure(path: dirA.path, effectiveUID: geteuid() &+ 1)
        XCTAssertEqual(uidMismatchMetrics.fileCount, 0, "Files not owned by effectiveUID must be skipped")
    }

    func testSafetyGuardEngineAllBranches() throws {
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MacSweepSafetyBranches-\(UUID().uuidString)")
        let realHome = tempBase.appendingPathComponent("RealHome")
        let symlinkHome = tempBase.appendingPathComponent("SymlinkHome")
        let cachesDir = realHome.appendingPathComponent("Library/Caches/com.google.Chrome")
        let appSupportProtected = realHome.appendingPathComponent("Library/Application Support/MobileSync/Backup")
        let noPermParent = realHome.appendingPathComponent("Library/Caches/NoPermParent")
        let childInNoPerm = noPermParent.appendingPathComponent("child.cache")

        try FileManager.default.createDirectory(at: cachesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appSupportProtected, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: noPermParent, withIntermediateDirectories: true)
        try Data(repeating: 0x11, count: 1024).write(to: childInNoPerm)
        try FileManager.default.createSymbolicLink(at: symlinkHome, withDestinationURL: realHome)

        // Remove execute/search permission on noPermParent so lstat(childInNoPerm) fails with EACCES != ENOENT
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: noPermParent.path)

        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: noPermParent.path)
            try? FileManager.default.removeItem(at: tempBase)
        }

        // 1. Initialize SafetyGuardEngine with symlinkHome so resolvedHome != standardizedHome
        let simulatedRunning = RunningProcessGuard(
            runningBundleIdentifiers: ["com.google.chrome"],
            runningLocalizedAppNames: ["google chrome"],
            runningProcessExecutables: ["google chrome"]
        )
        let engine = SafetyGuardEngine(
            processGuard: simulatedRunning,
            homeDirectoryPath: symlinkHome.path
        )

        // 2. Evaluate protected cache component outside ~/Library/Caches and outside exclusionTree (hits protectedCacheComponents loop)
        let mobileSyncVerdict = engine.evaluate(
            path: appSupportProtected.path,
            category: .webAndElectronCaches,
            bundleIdentifier: "com.apple.MobileSync",
            displayName: "MobileSync",
            defaultReason: "Test"
        )
        XCTAssertFalse(mobileSyncVerdict.isAllowed)

        let cloudKitTokenPath = realHome.appendingPathComponent(
            "Library/Containers/com.example.app/Data/CloudKit/record.db")
        let cloudKitComponentVerdict = engine.evaluate(
            path: cloudKitTokenPath.path,
            category: .applicationCaches,
            bundleIdentifier: "com.example.app",
            displayName: "Example App",
            defaultReason: "Test"
        )
        XCTAssertFalse(cloudKitComponentVerdict.isAllowed)

        // 3. Evaluate /Library/Caches/com.apple.customdaemon (hits isProtectedAppleCacheIdentifier for /Library/Caches/)
        let sysAppleCacheVerdict = engine.evaluate(
            path: "/Library/Caches/com.apple.customdaemon",
            category: .applicationCaches,
            bundleIdentifier: "com.apple.customdaemon",
            displayName: "Apple Daemon",
            defaultReason: "Test"
        )
        XCTAssertFalse(sysAppleCacheVerdict.isAllowed)

        // 4. Evaluate running app with .applicationCaches, .xcodeJunk (keeps .safeAutoSelect), and .browserCaches (downgrades to .reviewRecommended)
        let runningCacheVerdict = engine.evaluate(
            path: cachesDir.path,
            category: .applicationCaches,
            bundleIdentifier: "com.google.Chrome",
            displayName: "Google Chrome",
            defaultReason: "Chrome cache"
        )
        XCTAssertTrue(runningCacheVerdict.isAllowed)
        XCTAssertTrue(runningCacheVerdict.isRunningApp)
        XCTAssertEqual(runningCacheVerdict.confidence, .safeAutoSelect)

        let runningXcodeVerdict = engine.evaluate(
            path: cachesDir.path,
            category: .xcodeJunk,
            bundleIdentifier: "com.google.Chrome",
            displayName: "Google Chrome",
            defaultReason: "Xcode cache"
        )
        XCTAssertTrue(runningXcodeVerdict.isAllowed)
        XCTAssertTrue(runningXcodeVerdict.isRunningApp)
        XCTAssertEqual(runningXcodeVerdict.confidence, .safeAutoSelect)

        let runningBrowserVerdict = engine.evaluate(
            path: cachesDir.path,
            category: .browserCaches,
            bundleIdentifier: "com.google.Chrome",
            displayName: "Google Chrome",
            defaultReason: "Chrome browser cache"
        )
        XCTAssertTrue(runningBrowserVerdict.isAllowed)
        XCTAssertTrue(runningBrowserVerdict.isRunningApp)
        XCTAssertEqual(runningBrowserVerdict.confidence, .reviewRecommended)

        // 5. isPathUserDeletable with empty path (ENOENT -> true), EACCES child, and mismatched effectiveUID
        XCTAssertTrue(SafetyGuardEngine.isPathUserDeletable(""))
        XCTAssertFalse(SafetyGuardEngine.isPathUserDeletable(childInNoPerm.path), "lstat EACCES must return false")
        XCTAssertFalse(
            SafetyGuardEngine.isPathUserDeletable(cachesDir.path, effectiveUID: geteuid() &+ 1),
            "Mismatched effectiveUID must return false"
        )
    }

    func testSafeTrashCleanerAllBranchesAndMoveToTrash() throws {
        // 1. Test default init and FileManager.trashItem fallback using a sandboxed FileManager subclass
        final class SandboxedTrashFileManager: FileManager {
            override func trashItem(
                at url: URL, resultingItemURL outResultingURL: AutoreleasingUnsafeMutablePointer<NSURL?>?
            ) throws {
                try removeItem(at: url)
            }
        }
        let defaultCleaner = SafeTrashCleaner()
        XCTAssertEqual(defaultCleaner.execute(items: [], mode: .dryRunPreview).processedItemsCount, 0)

        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MacSweepCleanerBranches-\(UUID().uuidString)")
        let cachesDir = tempRoot.appendingPathComponent("Library/Caches")
        let trashableDir = cachesDir.appendingPathComponent("com.example.trashable")
        let protectedNameDir = cachesDir.appendingPathComponent("com.example.normal")
        let geoServicesTarget = tempRoot.appendingPathComponent("GeoServices")
        let partialDir = cachesDir.appendingPathComponent("com.example.partial")
        let aclFallbackDir = cachesDir.appendingPathComponent("com.example.aclfallback")
        let aclEmptyFailDir = cachesDir.appendingPathComponent("com.example.aclemptyfail")
        let aclTrulyEmptyFailDir = cachesDir.appendingPathComponent("com.example.acltrulyempty")
        let singleFailFile = cachesDir.appendingPathComponent("com.example.singlefail.cache")

        for dir in [
            trashableDir, protectedNameDir, geoServicesTarget, partialDir, aclFallbackDir, aclEmptyFailDir,
            aclTrulyEmptyFailDir,
        ] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        try Data(repeating: 0x11, count: 4096).write(to: trashableDir.appendingPathComponent("file.cache"))
        try Data(repeating: 0x22, count: 4096).write(to: singleFailFile)

        let engine = SafetyGuardEngine(homeDirectoryPath: tempRoot.path)

        // 2. Test .moveToTrash using a custom mock trashHandler (zero side effects on real ~/.Trash)
        final class TrashRecorder: @unchecked Sendable {
            var trashedURLs: [URL] = []
        }
        let recorder = TrashRecorder()
        let mockTrashCleaner = SafeTrashCleaner(safetyEngine: engine) { url in
            recorder.trashedURLs.append(url)
            try FileManager.default.removeItem(at: url)
        }

        let trashCandidate = ScanCandidateItem(
            path: trashableDir.path,
            category: .applicationCaches,
            bundleIdentifier: "com.example.trashable",
            appDisplayName: "Trashable App",
            itemName: "Cache",
            allocatedBytes: 4096,
            fileCount: 1,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: false,
            ruleIdentifier: "test.trash",
            safetyExplanation: "Safe"
        )
        let trashSummary = mockTrashCleaner.execute(items: [trashCandidate], mode: .moveToTrash)
        XCTAssertEqual(trashSummary.processedItemsCount, 1)
        XCTAssertEqual(recorder.trashedURLs.count, 1)

        // Also test default nil trashHandler path via SandboxedTrashFileManager
        try FileManager.default.createDirectory(at: trashableDir, withIntermediateDirectories: true)
        try Data(repeating: 0x11, count: 4096).write(to: trashableDir.appendingPathComponent("file2.cache"))
        let defaultHandlerCleaner = SafeTrashCleaner(safetyEngine: engine)
        let defaultHandlerSummary = defaultHandlerCleaner.execute(
            items: [trashCandidate],
            mode: .moveToTrash,
            fileManager: SandboxedTrashFileManager()
        )
        XCTAssertEqual(defaultHandlerSummary.processedItemsCount, 1)

        // 3. Already-removed item on disk (fileExists == false) is treated as already cleaned and pruned from UI
        let missingSummary = mockTrashCleaner.execute(items: [trashCandidate], mode: .permanentDelete)
        XCTAssertEqual(missingSummary.processedItemsCount, 1)

        // 4. Symlink whose target has a protected cache component name ("GeoServices")
        try FileManager.default.removeItem(at: protectedNameDir)
        try FileManager.default.createSymbolicLink(at: protectedNameDir, withDestinationURL: geoServicesTarget)
        let symlinkProtectedCandidate = ScanCandidateItem(
            path: protectedNameDir.path,
            category: .applicationCaches,
            bundleIdentifier: "com.example.normal",
            appDisplayName: "Normal",
            itemName: "Normal",
            allocatedBytes: 4096,
            fileCount: 1,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: false,
            ruleIdentifier: "test.symprotected",
            safetyExplanation: "Safe"
        )
        let symSummary = mockTrashCleaner.execute(items: [symlinkProtectedCandidate], mode: .permanentDelete)
        XCTAssertEqual(symSummary.skippedProtectedCount, 1)

        // 5. Partial directory cleanup (ancestor of excluded MobileSync) where a sibling child removal throws an error
        let appSupportDir = tempRoot.appendingPathComponent("Library/Application Support")
        let mobileSyncSubdir = appSupportDir.appendingPathComponent("MobileSync")
        let failingChild = appSupportDir.appendingPathComponent("failing_child.cache")
        try FileManager.default.createDirectory(at: mobileSyncSubdir, withIntermediateDirectories: true)
        try Data(repeating: 0x33, count: 4096).write(to: failingChild)

        let selectiveFailCleaner = SafeTrashCleaner(safetyEngine: engine) { url in
            if url.lastPathComponent == "failing_child.cache" {
                throw NSError(
                    domain: NSPOSIXErrorDomain, code: Int(EPERM),
                    userInfo: [NSLocalizedDescriptionKey: "Simulated child failure"])
            }
            try FileManager.default.removeItem(at: url)
        }
        let partialCandidate = ScanCandidateItem(
            path: appSupportDir.path,
            category: .applicationCaches,
            bundleIdentifier: "com.example.partial",
            appDisplayName: "Partial",
            itemName: "Partial",
            allocatedBytes: 4096,
            fileCount: 1,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: false,
            ruleIdentifier: "test.partialfail",
            safetyExplanation: "Safe"
        )
        let partialFailSummary = selectiveFailCleaner.execute(items: [partialCandidate], mode: .moveToTrash)
        XCTAssertEqual(partialFailSummary.errors.count, 1)

        // 6. Top-level directory removal fails, triggering ACL child fallback where a child succeeds,
        //    plus a second directory where all children fail, plus a single file that fails.
        let aclChildSuccess = aclFallbackDir.appendingPathComponent("reclaimable_child.cache")
        let aclChildProtected = aclFallbackDir.appendingPathComponent("CloudKit")
        try Data(repeating: 0x44, count: 8192).write(to: aclChildSuccess)
        try FileManager.default.createDirectory(at: aclChildProtected, withIntermediateDirectories: true)

        let aclChildFail = aclEmptyFailDir.appendingPathComponent("locked_child.cache")
        try Data(repeating: 0x55, count: 4096).write(to: aclChildFail)

        // Put a protected child in aclTrulyEmptyFailDir so childRemovedCount == 0, !children.isEmpty, and lastChildError == nil
        let aclProtectedOnlyChild = aclTrulyEmptyFailDir.appendingPathComponent("CloudKit")
        try FileManager.default.createDirectory(at: aclProtectedOnlyChild, withIntermediateDirectories: true)

        let aclCleaner = SafeTrashCleaner(safetyEngine: engine) { url in
            let name = url.lastPathComponent
            if name == "com.example.aclfallback" || name == "com.example.aclemptyfail"
                || name == "com.example.acltrulyempty" || name == "locked_child.cache"
                || name == "com.example.singlefail.cache"
            {
                throw NSError(
                    domain: NSPOSIXErrorDomain, code: Int(EACCES),
                    userInfo: [NSLocalizedDescriptionKey: "Simulated ACL restriction"])
            }
            try FileManager.default.removeItem(at: url)
        }

        let aclTrulyEmptyCandidate = ScanCandidateItem(
            path: aclTrulyEmptyFailDir.path,
            category: .applicationCaches,
            bundleIdentifier: "com.example.acltrulyempty",
            appDisplayName: "ACL Truly Empty",
            itemName: "ACL Truly Empty",
            allocatedBytes: 4096,
            fileCount: 1,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: false,
            ruleIdentifier: "test.acl.empty",
            safetyExplanation: "Safe"
        )

        let aclSuccessCandidate = ScanCandidateItem(
            path: aclFallbackDir.path,
            category: .applicationCaches,
            bundleIdentifier: "com.example.aclfallback",
            appDisplayName: "ACL Fallback",
            itemName: "ACL Fallback",
            allocatedBytes: 8192,
            fileCount: 1,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: false,
            ruleIdentifier: "test.acl1",
            safetyExplanation: "Safe"
        )
        let aclFailCandidate = ScanCandidateItem(
            path: aclEmptyFailDir.path,
            category: .applicationCaches,
            bundleIdentifier: "com.example.aclemptyfail",
            appDisplayName: "ACL Empty Fail",
            itemName: "ACL Empty Fail",
            allocatedBytes: 4096,
            fileCount: 1,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: false,
            ruleIdentifier: "test.acl2",
            safetyExplanation: "Safe"
        )
        let singleFailCandidate = ScanCandidateItem(
            path: singleFailFile.path,
            category: .applicationCaches,
            bundleIdentifier: "com.example.singlefail",
            appDisplayName: "Single Fail",
            itemName: "Single Fail",
            allocatedBytes: 4096,
            fileCount: 1,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: false,
            ruleIdentifier: "test.singlefail",
            safetyExplanation: "Safe"
        )

        var progressFractions: [Double] = []
        let aclSummary = aclCleaner.execute(
            items: [aclSuccessCandidate, aclFailCandidate, aclTrulyEmptyCandidate, singleFailCandidate],
            mode: .moveToTrash,
            onProgressUpdate: { fraction, _ in
                progressFractions.append(fraction)
            }
        )
        XCTAssertEqual(aclSummary.processedItemsCount, 1, "aclFallbackDir should succeed via child fallback")
        XCTAssertEqual(
            aclSummary.errors.count, 3, "aclEmptyFailDir, aclTrulyEmptyFailDir, and singleFailFile should record errors"
        )
        XCTAssertFalse(progressFractions.isEmpty)
        XCTAssertEqual(progressFractions.last ?? 0.0, 1.0, accuracy: 0.0001)

        // Exercise computeFraction when totalSelectedBytes == 0
        let zeroBytesCandidate = ScanCandidateItem(
            path: aclFallbackDir.path,
            category: .applicationCaches,
            bundleIdentifier: "com.example.zero",
            appDisplayName: "Zero",
            itemName: "Zero",
            allocatedBytes: 0,
            fileCount: 1,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: false,
            ruleIdentifier: "test.zero",
            safetyExplanation: "Safe"
        )
        _ = aclCleaner.execute(items: [zeroBytesCandidate], mode: .dryRunPreview, onProgressUpdate: { _, _ in })
    }

    func testRunningProcessGuardAndCoordinatorAllBranches() async throws {
        // 1. RunningProcessGuard.captureCurrentSnapshot() default initializer and matching branches
        let liveGuard = RunningProcessGuard.captureCurrentSnapshot()
        XCTAssertFalse(liveGuard.isActive(bundleIdentifier: "", displayName: ""))

        let customGuard = RunningProcessGuard(
            runningBundleIdentifiers: ["com.example.activebundle"],
            runningLocalizedAppNames: ["active display app"],
            runningProcessExecutables: ["activeproc"]
        )
        XCTAssertTrue(customGuard.isActive(bundleIdentifier: "com.example.activebundle", displayName: "Other"))
        XCTAssertTrue(customGuard.isActive(bundleIdentifier: "other.id", displayName: "Active Display App"))
        XCTAssertTrue(
            customGuard.isActive(bundleIdentifier: "other.id", displayName: "other", processNames: ["ActiveProc"]))
        XCTAssertFalse(
            customGuard.isActive(bundleIdentifier: "unrelated.id", displayName: "Unrelated", processNames: ["none"]))

        // 2. Mock RunningApplicationControlling to test liveRunningAppDescriptors & terminateApplications safely
        final class MockRunningApp: RunningApplicationControlling {
            var isTerminated: Bool
            var bundleIdentifier: String?
            var localizedName: String?
            var bundleURL: URL?
            var executableURL: URL?
            var processIdentifier: pid_t
            var activationPolicy: NSApplication.ActivationPolicy
            var terminateCalled = false
            var forceTerminateCalled = false
            var terminateKillsImmediately: Bool
            var forceTerminateKills: Bool

            init(
                isTerminated: Bool = false,
                bundleIdentifier: String? = "com.example.mockapp",
                localizedName: String? = "Mock App",
                bundleURL: URL? = URL(fileURLWithPath: "/Applications/MockApp.app"),
                executableURL: URL? = nil,
                processIdentifier: pid_t = 7777,
                activationPolicy: NSApplication.ActivationPolicy = .regular,
                terminateKillsImmediately: Bool = true,
                forceTerminateKills: Bool = true
            ) {
                self.isTerminated = isTerminated
                self.bundleIdentifier = bundleIdentifier
                self.localizedName = localizedName
                self.bundleURL = bundleURL
                self.executableURL = executableURL
                self.processIdentifier = processIdentifier
                self.activationPolicy = activationPolicy
                self.terminateKillsImmediately = terminateKillsImmediately
                self.forceTerminateKills = forceTerminateKills
            }

            func terminate() -> Bool {
                terminateCalled = true
                if terminateKillsImmediately {
                    isTerminated = true
                }
                return true
            }

            func forceTerminate() -> Bool {
                forceTerminateCalled = true
                if forceTerminateKills {
                    isTerminated = true
                }
                return true
            }
        }

        // Test liveRunningAppDescriptors with default parameter and with mock apps
        _ = RunningAppCleanupCoordinator.liveRunningAppDescriptors()

        let mockApps: [any RunningApplicationControlling] = [
            MockRunningApp(isTerminated: true),
            MockRunningApp(bundleIdentifier: nil),
            MockRunningApp(bundleIdentifier: ""),
            MockRunningApp(bundleIdentifier: "com.apple.finder"),
            MockRunningApp(bundleIdentifier: "com.example.bg", activationPolicy: .accessory),
            MockRunningApp(
                bundleIdentifier: "com.example.nolocalname",
                localizedName: nil,
                bundleURL: URL(fileURLWithPath: "/Applications/NoLocalName.app")
            ),
            MockRunningApp(
                bundleIdentifier: "com.example.nobundleurl",
                localizedName: nil,
                bundleURL: nil
            ),
        ]
        let descriptors = RunningAppCleanupCoordinator.liveRunningAppDescriptors(workspaceApps: mockApps)
        XCTAssertEqual(descriptors.count, 2)
        XCTAssertEqual(descriptors[0].localizedName, "NoLocalName")
        XCTAssertEqual(descriptors[1].localizedName, "com.example.nobundleurl")

        // 3. Test detectConflicts edge cases: empty items, no regular running apps, catalog resolution, and displayName fallback
        XCTAssertTrue(RunningAppCleanupCoordinator.detectConflicts(for: []).isEmpty)

        let itemByName = ScanCandidateItem(
            path: "/Users/testuser/Library/Caches/custom_folder",
            category: .applicationCaches,
            bundleIdentifier: "unknown.folder.id",
            appDisplayName: "CustomApp",
            itemName: "Cache",
            allocatedBytes: 4096,
            fileCount: 1,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: true,
            ruleIdentifier: "test.name",
            safetyExplanation: "Safe",
            isSelected: true
        )
        let itemByCatalogAppName = ScanCandidateItem(
            path: "/Users/testuser/Library/Caches/vs_code_ext",
            category: .applicationCaches,
            bundleIdentifier: "unknown.vscode.ext",
            appDisplayName: "code",
            itemName: "Ext",
            allocatedBytes: 4096,
            fileCount: 1,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: true,
            ruleIdentifier: "test.vscode",
            safetyExplanation: "Safe",
            isSelected: true
        )

        let itemByBundleAlias = ScanCandidateItem(
            path: "/Users/testuser/Library/Caches/rave_cache",
            category: .applicationCaches,
            bundleIdentifier: "rave",
            appDisplayName: "UnknownDisplay",
            itemName: "Rave Cache",
            allocatedBytes: 4096,
            fileCount: 1,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: true,
            ruleIdentifier: "test.rave",
            safetyExplanation: "Safe",
            isSelected: true
        )

        let onlyFinderRunning = [
            RunningAppDescriptor(
                bundleIdentifier: "com.apple.finder",
                localizedName: "Finder",
                bundlePath: "/System/Library/CoreServices/Finder.app",
                processIdentifier: 100,
                isRegularApp: true
            )
        ]
        XCTAssertTrue(
            RunningAppCleanupCoordinator.detectConflicts(for: [itemByName], runningApps: onlyFinderRunning).isEmpty
        )
        // Also invoke detectConflicts with runningApps: nil (default liveRunningAppDescriptors fallback)
        _ = RunningAppCleanupCoordinator.detectConflicts(for: [itemByName], runningApps: nil)

        let customRunning = [
            RunningAppDescriptor(
                bundleIdentifier: "com.vendor.custom",
                localizedName: "CustomApp",
                bundlePath: "/Applications/CustomApp.app",
                processIdentifier: 501,
                isRegularApp: true
            ),
            RunningAppDescriptor(
                bundleIdentifier: "com.microsoft.VSCode",
                localizedName: "Visual Studio Code",
                bundlePath: nil,
                processIdentifier: 502,
                isRegularApp: true
            ),
            RunningAppDescriptor(
                bundleIdentifier: "io.rave.desktop",
                localizedName: "Rave",
                bundlePath: nil,
                processIdentifier: 503,
                isRegularApp: true
            ),
        ]
        let xcodeUnmatchedItem = ScanCandidateItem(
            path: "/Users/testuser/Library/Developer/Xcode/DerivedData/Unmatched",
            category: .xcodeJunk,
            bundleIdentifier: "com.apple.dt.Xcode",
            appDisplayName: "Xcode",
            itemName: "Unmatched Xcode Cache",
            allocatedBytes: 4096,
            fileCount: 1,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: false,
            ruleIdentifier: "test.xcode.unmatched",
            safetyExplanation: "Safe",
            isSelected: true
        )
        let detected = RunningAppCleanupCoordinator.detectConflicts(
            for: [itemByName, itemByCatalogAppName, itemByBundleAlias, xcodeUnmatchedItem],
            runningApps: customRunning
        )
        XCTAssertEqual(detected.count, 3)
        XCTAssertEqual(detected[0].id, detected[0].bundleIdentifier.lowercased())

        // 4. Test terminateApplications: empty conflicts, default provider with fake conflict, graceful exit, and forceTerminate
        let emptyTerm = await RunningAppCleanupCoordinator.terminateApplications([])
        XCTAssertTrue(emptyTerm.isEmpty)

        let fakeConflict = RunningApplicationConflict(
            bundleIdentifier: "com.nonexistent.macsweep.test.\(UUID().uuidString)",
            displayName: "Fake App",
            bundlePath: nil,
            processIdentifier: 99999,
            affectedItemsCount: 1,
            affectedAllocatedBytes: 1024,
            affectedItemIDs: ["1"]
        )
        // Exercises the default `workspaceAppsProvider` closure safely without matching any real running app
        let defaultProviderTerm = await RunningAppCleanupCoordinator.terminateApplications(
            [fakeConflict], timeoutSeconds: 0.01)
        XCTAssertEqual(defaultProviderTerm.count, 1)

        // Exercise graceful termination that succeeds on first poll
        let gracefulApp = MockRunningApp(
            bundleIdentifier: "com.example.graceful",
            terminateKillsImmediately: true
        )
        let gracefulConflict = RunningApplicationConflict(
            bundleIdentifier: "com.example.graceful",
            displayName: "Graceful",
            bundlePath: nil,
            processIdentifier: 1111,
            affectedItemsCount: 1,
            affectedAllocatedBytes: 1024,
            affectedItemIDs: ["g1"]
        )
        let gracefulTerminated = await RunningAppCleanupCoordinator.terminateApplications(
            [gracefulConflict],
            forceIfNeeded: true,
            timeoutSeconds: 0.5,
            workspaceAppsProvider: { [gracefulApp] }
        )
        XCTAssertTrue(gracefulApp.terminateCalled)
        XCTAssertFalse(gracefulApp.forceTerminateCalled)
        XCTAssertTrue(gracefulTerminated.contains("com.example.graceful"))

        // Exercise stubborn app that ignores terminate(), loops until timeout, and gets forceTerminated
        let stubbornApp = MockRunningApp(
            bundleIdentifier: "com.example.stubborn",
            terminateKillsImmediately: false,
            forceTerminateKills: false
        )
        let alreadyTerminatedApp = MockRunningApp(
            isTerminated: true,
            bundleIdentifier: "com.example.stubborn"
        )
        let stubbornConflict = RunningApplicationConflict(
            bundleIdentifier: "com.example.stubborn",
            displayName: "Stubborn",
            bundlePath: nil,
            processIdentifier: 2222,
            affectedItemsCount: 1,
            affectedAllocatedBytes: 1024,
            affectedItemIDs: ["s1"]
        )
        let stubbornTerminated = await RunningAppCleanupCoordinator.terminateApplications(
            [stubbornConflict],
            forceIfNeeded: true,
            timeoutSeconds: 0.15,
            workspaceAppsProvider: { [stubbornApp, alreadyTerminatedApp] }
        )
        XCTAssertTrue(stubbornApp.terminateCalled)
        XCTAssertTrue(stubbornApp.forceTerminateCalled)
        XCTAssertFalse(stubbornTerminated.contains("com.example.stubborn"))
    }

    @MainActor
    func testFullDiskAccessPermissionHelperAllBranches() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MacSweepFDABranches-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }

        // 1. No TCC probe directories exist -> returns true (fresh test home directory)
        XCTAssertTrue(FullDiskAccessPermissionHelper.hasFullDiskAccess(homeDirectoryPath: tempHome.path))

        // 2. Safari directory exists and is readable -> returns true
        let safariDir = tempHome.appendingPathComponent("Library/Safari")
        try FileManager.default.createDirectory(at: safariDir, withIntermediateDirectories: true)
        XCTAssertTrue(FullDiskAccessPermissionHelper.hasFullDiskAccess(homeDirectoryPath: tempHome.path))

        // 3. Safari directory exists but has 000 permissions -> contentsOfDirectory fails -> returns false
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: safariDir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: safariDir.path) }

        XCTAssertFalse(FullDiskAccessPermissionHelper.hasFullDiskAccess(homeDirectoryPath: tempHome.path))

        // 4. Test openSystemSettingsFullDiskAccess using MockWorkspace
        final class MockWorkspace: WorkspaceURLOpening {
            var openedURL: URL?
            func open(_ url: URL) -> Bool {
                openedURL = url
                return true
            }
        }
        let mockWorkspace = MockWorkspace()
        FullDiskAccessPermissionHelper.openSystemSettingsFullDiskAccess(workspace: mockWorkspace)
        XCTAssertEqual(mockWorkspace.openedURL, FullDiskAccessPermissionHelper.systemSettingsDeepLinkURL)
    }

    func testScanModelsExhaustiveMethodsAndUpgrades() {
        // 1. ScanScope & CleanupCategory properties
        for scope in ScanScope.allCases {
            XCTAssertEqual(scope.id, scope.rawValue)
            XCTAssertFalse(scope.title.isEmpty)
            XCTAssertFalse(scope.shortDescription.isEmpty)
            XCTAssertFalse(scope.description.isEmpty)
            XCTAssertFalse(scope.highlightBadges.isEmpty)
            XCTAssertFalse(scope.safetyNote.isEmpty)
            XCTAssertFalse(scope.systemSymbolName.isEmpty)
        }
        for category in CleanupCategory.allCases {
            XCTAssertEqual(category.id, category.rawValue)
            XCTAssertFalse(category.subtitle.isEmpty)
            XCTAssertFalse(category.systemSymbolName.isEmpty)
            _ = category.scope
        }
        XCTAssertTrue(SafetyConfidence.safeAutoSelect < SafetyConfidence.reviewRecommended)
        XCTAssertTrue(SafetyConfidence.reviewRecommended < SafetyConfidence.blocked)
        for confidence in [SafetyConfidence.safeAutoSelect, .reviewRecommended, .blocked] {
            for lang in AppLanguage.allCases {
                XCTAssertFalse(confidence.badgeTitle(in: lang).isEmpty)
            }
        }
        for filter in ConfidenceFilter.allCases {
            XCTAssertEqual(filter.id, filter.rawValue)
            XCTAssertFalse(filter.systemSymbolName.isEmpty)
            for lang in AppLanguage.allCases {
                XCTAssertFalse(filter.title(in: lang).isEmpty)
            }
        }
        XCTAssertTrue(ConfidenceFilter.all.matches(.safeAutoSelect))
        XCTAssertTrue(ConfidenceFilter.all.matches(.reviewRecommended))
        XCTAssertTrue(ConfidenceFilter.safeOnly.matches(.safeAutoSelect))
        XCTAssertFalse(ConfidenceFilter.safeOnly.matches(.reviewRecommended))
        XCTAssertTrue(ConfidenceFilter.needsReview.matches(.reviewRecommended))
        XCTAssertFalse(ConfidenceFilter.needsReview.matches(.safeAutoSelect))

        // 2. ScanCandidateItem, ApplicationBundleGroup, CleanupCategoryGroup, and ScanReport methods
        let aiItem = ScanCandidateItem(
            path: "/Users/testuser/.cache/huggingface",
            category: .developerToolchains,
            bundleIdentifier: "co.huggingface.cache",
            appDisplayName: "Hugging Face Cache",
            itemName: "Hugging Face Hub Cache",
            allocatedBytes: 4_000_000,
            fileCount: 10,
            lastModified: Date(),
            confidence: .reviewRecommended,
            isRunningApp: false,
            ruleIdentifier: "ai.huggingface_cache",
            safetyExplanation: "Hugging Face cache",
            isSelected: true
        )
        let devItem = ScanCandidateItem(
            path: "/Users/testuser/.npm/_cacache",
            category: .developerToolchains,
            bundleIdentifier: "org.nodejs.npm",
            appDisplayName: "npm",
            itemName: "npm Cache",
            allocatedBytes: 2_000_000,
            fileCount: 50,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: false,
            ruleIdentifier: "js.npm_cacache",
            safetyExplanation: "npm cache",
            isSelected: true
        )
        let cacheItem = ScanCandidateItem(
            path: "/Users/testuser/Library/Caches/com.example.app",
            category: .applicationCaches,
            bundleIdentifier: "com.example.app",
            appDisplayName: "Example App",
            itemName: "App Cache",
            allocatedBytes: 1_000_000,
            fileCount: 5,
            lastModified: Date(),
            confidence: .safeAutoSelect,
            isRunningApp: false,
            ruleIdentifier: "cache.app",
            safetyExplanation: "App cache",
            isSelected: false
        )

        let aiGroup = ApplicationBundleGroup(
            category: .developerToolchains,
            bundleIdentifier: "co.huggingface.cache",
            appDisplayName: "Hugging Face Cache",
            bundlePath: nil,
            isRunning: false,
            items: [aiItem]
        )
        let devGroup = ApplicationBundleGroup(
            category: .developerToolchains,
            bundleIdentifier: "org.nodejs.npm",
            appDisplayName: "npm",
            bundlePath: nil,
            isRunning: false,
            items: [devItem]
        )
        let cacheGroup = ApplicationBundleGroup(
            category: .applicationCaches,
            bundleIdentifier: "com.example.app",
            appDisplayName: "Example App",
            bundlePath: "/Applications/Example.app",
            isRunning: false,
            items: [cacheItem]
        )
        let emptyGroup = ApplicationBundleGroup(
            category: .applicationCaches,
            bundleIdentifier: "com.example.empty",
            appDisplayName: "Empty App",
            bundlePath: nil,
            isRunning: false,
            items: []
        )
        XCTAssertFalse(emptyGroup.isAllSelected)
        XCTAssertFalse(emptyGroup.isPartiallySelected)
        XCTAssertEqual(emptyGroup.primaryConfidence, .safeAutoSelect)
        XCTAssertEqual(aiGroup.primaryConfidence, .reviewRecommended)
        XCTAssertEqual(aiGroup.selectedReviewItemCount, 1)
        XCTAssertEqual(aiGroup.selectedItemCount, 1)
        XCTAssertEqual(aiGroup.selectedReviewBytes, 4_000_000)
        XCTAssertTrue(aiGroup.matches(confidenceFilter: .needsReview))
        XCTAssertFalse(aiGroup.matches(confidenceFilter: .safeOnly))
        XCTAssertTrue(devGroup.isAllSelected)
        XCTAssertFalse(devGroup.isPartiallySelected)

        let mixedGroup = ApplicationBundleGroup(
            category: .developerToolchains,
            bundleIdentifier: "com.example.mixed",
            appDisplayName: "Mixed",
            bundlePath: nil,
            isRunning: false,
            items: [devItem, cacheItem]
        )
        XCTAssertFalse(mixedGroup.isAllSelected)
        XCTAssertTrue(mixedGroup.isPartiallySelected)

        let devCategoryGroup = CleanupCategoryGroup(
            category: .developerToolchains,
            appGroups: [aiGroup, devGroup]
        )
        let cacheCategoryGroup = CleanupCategoryGroup(
            category: .applicationCaches,
            appGroups: [cacheGroup]
        )
        let emptyCategoryGroup = CleanupCategoryGroup(
            category: .browserCaches,
            appGroups: []
        )
        XCTAssertFalse(emptyCategoryGroup.isAllSelected)
        XCTAssertFalse(emptyCategoryGroup.isPartiallySelected)
        XCTAssertEqual(devCategoryGroup.id, CleanupCategory.developerToolchains.rawValue)
        XCTAssertEqual(devCategoryGroup.totalItemCount, 2)
        XCTAssertEqual(devCategoryGroup.totalFileCount, 60)
        XCTAssertEqual(devCategoryGroup.safeAutoSelectBytes, 2_000_000)
        XCTAssertEqual(devCategoryGroup.reviewRecommendedBytes, 4_000_000)
        XCTAssertTrue(devCategoryGroup.isAllSelected)
        XCTAssertFalse(devCategoryGroup.isPartiallySelected)
        XCTAssertEqual(devCategoryGroup.appGroups(matching: .all).count, 2)
        XCTAssertEqual(devCategoryGroup.appGroups(matching: .safeOnly).count, 1)
        XCTAssertEqual(devCategoryGroup.appGroupCount(matching: .needsReview), 1)
        XCTAssertEqual(devCategoryGroup.reviewAppGroupCount, 1)
        XCTAssertEqual(devCategoryGroup.safeAppGroupCount, 1)
        XCTAssertEqual(devCategoryGroup.selectedReviewItemCount, 1)
        XCTAssertEqual(devCategoryGroup.selectedItemCount, 2)
        XCTAssertEqual(devCategoryGroup.selectedReviewBytes, 4_000_000)

        let partialCategoryGroup = CleanupCategoryGroup(
            category: .applicationCaches,
            appGroups: [devGroup, cacheGroup]
        )
        XCTAssertFalse(partialCategoryGroup.isAllSelected)
        XCTAssertTrue(partialCategoryGroup.isPartiallySelected)

        let legacyReport = ScanReport(
            generatedAt: Date(),
            scanDurationSeconds: 0.25,
            categories: [devCategoryGroup, cacheCategoryGroup],
            protectedPathsSkippedCount: 3,
            runningAppsDetectedCount: 1
        )
        XCTAssertEqual(legacyReport.grandTotalBytes, 7_000_000)
        XCTAssertEqual(legacyReport.selectedTotalBytes, 6_000_000)
        XCTAssertEqual(legacyReport.safeAutoSelectedBytes, 3_000_000)
        XCTAssertEqual(legacyReport.reviewRecommendedBytes, 4_000_000)
        XCTAssertEqual(legacyReport.totalCandidateCount, 3)
        XCTAssertEqual(legacyReport.totalSelectedCount, 2)
        XCTAssertEqual(legacyReport.totalFileCount, 65)
        XCTAssertEqual(legacyReport.selectedReviewItemCount, 1)
        XCTAssertEqual(legacyReport.selectedReviewBytes, 4_000_000)
        XCTAssertEqual(legacyReport.appGroupCount(matching: .all), 3)

        // Upgrade legacy report that had AI items inside .developerToolchains
        let upgraded = legacyReport.upgradedWithAICategory()
        XCTAssertTrue(upgraded.categories.contains { $0.category == .aiAndAgentRuntimes })
        XCTAssertTrue(upgraded.categories.contains { $0.category == .developerToolchains })

        // Calling upgradedWithAICategory() when .aiAndAgentRuntimes already exists returns self immediately
        let reUpgraded = upgraded.upgradedWithAICategory()
        XCTAssertEqual(reUpgraded.categories.count, upgraded.categories.count)

        // Upgrade legacy report where ALL items in .developerToolchains are AI items
        let onlyAIDevGroup = CleanupCategoryGroup(category: .developerToolchains, appGroups: [aiGroup])
        let onlyAILegacyReport = ScanReport(
            generatedAt: Date(),
            scanDurationSeconds: 0.1,
            categories: [onlyAIDevGroup],
            protectedPathsSkippedCount: 0,
            runningAppsDetectedCount: 0
        )
        let onlyAIUpgraded = onlyAILegacyReport.upgradedWithAICategory()
        XCTAssertEqual(onlyAIUpgraded.categories.map(\.category), [.aiAndAgentRuntimes])

        // Upgrade legacy report where NO items in .developerToolchains are AI items
        let noAIDevGroup = CleanupCategoryGroup(category: .developerToolchains, appGroups: [devGroup])
        let noAILegacyReport = ScanReport(
            generatedAt: Date(),
            scanDurationSeconds: 0.1,
            categories: [noAIDevGroup],
            protectedPathsSkippedCount: 0,
            runningAppsDetectedCount: 0
        )
        let noAIUpgraded = noAILegacyReport.upgradedWithAICategory()
        XCTAssertEqual(noAIUpgraded.categories.map(\.category), [.developerToolchains])

        // Scope helpers on ScanReport
        XCTAssertEqual(upgraded.categories(for: .developer).count, 1)
        XCTAssertEqual(upgraded.totalAllocatedBytes(for: .developer), 2_000_000)
        XCTAssertEqual(upgraded.selectedAllocatedBytes(for: .developer), 2_000_000)
        XCTAssertTrue(upgraded.isScopeAllSelected(.developer))
        XCTAssertFalse(upgraded.isScopePartiallySelected(.developer))
        XCTAssertFalse(upgraded.isScopeAllSelected(.general))
        XCTAssertFalse(upgraded.isScopePartiallySelected(.general))

        let emptyScopeReport = ScanReport(
            generatedAt: Date(),
            scanDurationSeconds: 0.1,
            categories: [],
            protectedPathsSkippedCount: 0,
            runningAppsDetectedCount: 0
        )
        XCTAssertFalse(emptyScopeReport.isScopeAllSelected(.general))
        XCTAssertFalse(emptyScopeReport.isScopePartiallySelected(.general))

        let partialScopeReport = ScanReport(
            generatedAt: Date(),
            scanDurationSeconds: 0.1,
            categories: [partialCategoryGroup],
            protectedPathsSkippedCount: 0,
            runningAppsDetectedCount: 0
        )
        XCTAssertFalse(partialScopeReport.isScopeAllSelected(.general))
        XCTAssertTrue(partialScopeReport.isScopePartiallySelected(.general))

        // Test filtered(by:), totalBytes(for:), and removingItems(withIDs:)
        let devScopeReport = upgraded.filtered(by: [.developer])
        XCTAssertEqual(devScopeReport.categories.count, 1)
        XCTAssertEqual(upgraded.totalBytes(for: .general), 1_000_000)

        let unchangedReport = upgraded.removingItems(withIDs: [])
        XCTAssertEqual(unchangedReport.grandTotalBytes, upgraded.grandTotalBytes)

        // Remove only aiItem so two categories (.developerToolchains and .applicationCaches) remain and sort closure executes
        let twoCategoriesRemaining = upgraded.removingItems(withIDs: [aiItem.id])
        XCTAssertEqual(twoCategoriesRemaining.categories.count, 2)

        let afterRemoval = upgraded.removingItems(withIDs: [aiItem.id, cacheItem.id])
        XCTAssertEqual(afterRemoval.grandTotalBytes, 2_000_000)
        XCTAssertEqual(afterRemoval.safeAutoSelectedBytes, 2_000_000)
        XCTAssertEqual(afterRemoval.reviewRecommendedBytes, 0)
    }

    func testAllSubscannersComprehensiveCoverage() throws {
        // 1. Test all subscanners against an empty non-existent home directory to hit early-return guards
        let emptyHome = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MacSweepEmptyHome-\(UUID().uuidString)")
        let emptyEngine = SafetyGuardEngine(homeDirectoryPath: emptyHome.path)
        let emptyCatalog = ApplicationMetadataCatalog(homeDirectoryPath: emptyHome.path)

        for scanner in ScanOrchestrator(homeDirectoryPath: emptyHome.path).subscanners {
            let res = scanner.scan(safetyEngine: emptyEngine, appCatalog: emptyCatalog)
            XCTAssertTrue(res.candidates.isEmpty)
        }
        XCTAssertFalse(PreferenceAndStateHygieneSubscanner.isCorruptedPropertyList(atPath: "/nonexistent/file.plist"))

        // 2. Build a comprehensive sandboxed mock home directory covering every subscanner branch
        let mockHome = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MacSweepFullSubscanners-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: mockHome) }

        func makeDir(_ relPath: String) throws -> URL {
            let url = mockHome.appendingPathComponent(relPath)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        func writeData(_ relPath: String, bytes: Int = 65_536, ageSeconds: TimeInterval = 7200) throws -> URL {
            let url = mockHome.appendingPathComponent(relPath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 0x5A, count: bytes).write(to: url)
            let modDate = Date().addingTimeInterval(-ageSeconds)
            try FileManager.default.setAttributes([.modificationDate: modDate], ofItemAtPath: url.path)
            return url
        }

        // --- Subscanner 1: ApplicationCacheSubscanner ---
        // Standard user cache + Safari browser cache (skipped by AppCacheScanner) + Toolchain cache (skipped by AppCacheScanner)
        _ = try writeData("Library/Caches/com.example.standardapp/cache.db")
        _ = try writeData("Library/Caches/com.apple.Safari/WebKitCache/data.bin")
        _ = try writeData("Library/Caches/Homebrew/downloads/pkg.tar.gz")
        // Sandboxed container caches (valid, without Caches dir, empty Caches dir, and Apple container)
        _ = try writeData("Library/Containers/com.example.sandboxed/Data/Library/Caches/blob.bin")
        _ = try makeDir("Library/Containers/com.example.nocaches/Data/Library")
        _ = try makeDir("Library/Containers/com.example.emptycaches/Data/Library/Caches")
        _ = try makeDir("Library/Containers/com.example.emptycaches/Data/Library/Logs")
        _ = try makeDir("Library/Containers/com.apple.Notes/Data/Library/Caches")
        _ = try makeDir("Library/Containers/com.apple.Notes/Data/Library/Logs")
        // ~/.cache entries (one generic XDG cache, one toolchain-owned "uv" skipped by AppCacheScanner)
        _ = try writeData(".cache/custom_xdg_tool/index.bin")
        _ = try writeData(".cache/uv/wheels/pkg.whl")

        // --- Subscanner 2: ElectronAndWebAppCacheSubscanner ---
        // Standard Electron app ("Slack") + AI app ("Claude") + protected app support ("MobileSync") + top-level file
        _ = try writeData("Library/Application Support/Slack/Cache/Cache_Data/f_001")
        _ = try writeData("Library/Application Support/Slack/Code Cache/js/index.bin")
        _ = try writeData("Library/Application Support/Claude/Cache/data_0")
        _ = try writeData("Library/Application Support/MobileSync/Backup/Cache/secret.bin")
        _ = try writeData("Library/Application Support/top_level_file.txt")

        // --- Subscanner 3: DeveloperToolchainSubscanner ---
        // Include an AI recipe (.ollama/models), a standard dev recipe (.npm/_cacache), and CoreSimulator devices
        _ = try writeData(".ollama/models/blobs/sha256-model")
        _ = try writeData(".npm/_cacache/content-v2/sha512/tarball")

        _ = try makeDir("Library/Developer/CoreSimulator/Devices/NO-PLIST-UUID")
        let simUUID = "11111111-2222-3333-4444-555555555555"
        let simDeviceDir = try makeDir("Library/Developer/CoreSimulator/Devices/\(simUUID)")
        let devicePlist: [String: Any] = [
            "name": "iPhone 16 Pro",
            "runtime": "com.apple.CoreSimulator.SimRuntime.iOS-18-0",
        ]
        let devicePlistData = try PropertyListSerialization.data(
            fromPropertyList: devicePlist, format: .xml, options: 0)
        try devicePlistData.write(to: simDeviceDir.appendingPathComponent("device.plist"))
        _ = try writeData("Library/Developer/CoreSimulator/Devices/\(simUUID)/data/Library/Caches/simcache.bin")
        // Large >5MB data/Containers directory inside CoreSimulator device
        _ = try writeData(
            "Library/Developer/CoreSimulator/Devices/\(simUUID)/data/Containers/Bundle/Application/app.bin",
            bytes: 5_500_000)

        // --- Subscanner 4: LogsAndDiagnosticsSubscanner ---
        _ = try writeData("Library/Logs/DiagnosticReports/Retired/ignored.ips")
        _ = try writeData("Library/Logs/DiagnosticReports/CrashApp_2026.ips")
        _ = try writeData("Library/Logs/CrashReporter/Panics.crash")
        // Tiny recent log (<32KB and <5 min old) -> skipped by active log protection
        _ = try writeData("Library/Logs/TinyRecentApp/active.log", bytes: 512, ageSeconds: 10)
        // Older/larger log -> included
        _ = try writeData("Library/Logs/MyService/service.log", bytes: 65_536, ageSeconds: 3600)
        // Container logs (one older/larger included, one tiny recent skipped)
        _ = try writeData(
            "Library/Containers/com.example.sandboxed/Data/Library/Logs/container.log", bytes: 65_536, ageSeconds: 3600)
        _ = try writeData(
            "Library/Containers/com.example.sandboxed/Data/Library/Logs/tiny_active.log", bytes: 512, ageSeconds: 10)

        // --- Subscanner 5: BrowserCacheSubscanner ---
        // Direct browser cache (Safari & Chrome) + Chromium profile cache (Google Chrome Default & Profile 1 & Guest Profile & System Profile)
        _ = try writeData("Library/Caches/com.apple.Safari/fsCachedData/page.bin")
        _ = try writeData("Library/Caches/Google/Chrome/Default/Cache/data_1")
        _ = try writeData("Library/Application Support/Google/Chrome/Default/GPUCache/data_1")
        _ = try writeData("Library/Application Support/Google/Chrome/Profile 1/ShaderCache/wasm.bin")
        _ = try writeData("Library/Application Support/Google/Chrome/Guest Profile/GPUCache/guest.bin")
        _ = try writeData("Library/Application Support/Google/Chrome/System Profile/GPUCache/sys.bin")
        _ = try writeData("Library/Application Support/Google/Chrome/UnrelatedFolder/GPUCache/ignore.bin")

        // --- Subscanner 6: PreferenceAndStateHygieneSubscanner ---
        // Apple plist (skipped), valid plist, 0-byte plist, corrupted binary plist, non-plist file, and .plist subdirectory
        let validPlistURL = try makeDir("Library/Preferences").appendingPathComponent("com.example.valid.plist")
        _ = try makeDir("Library/Preferences/SubFolder.plist")
        try devicePlistData.write(to: validPlistURL)
        try devicePlistData.write(to: mockHome.appendingPathComponent("Library/Preferences/com.apple.Safari.plist"))
        _ = try writeData("Library/Preferences/com.example.empty.plist", bytes: 0)
        let corruptPlistURL = mockHome.appendingPathComponent("Library/Preferences/com.example.corrupt.plist")
        try Data("<<<NOT A VALID PLIST>>>".utf8).write(to: corruptPlistURL)
        _ = try writeData("Library/Preferences/README.txt", bytes: 128)

        // Saved Application State: one for running app (skipped), one for closed app (included), one 0-byte closed app (skipped)
        _ = try writeData("Library/Saved Application State/com.example.running.savedState/windows.plist")
        _ = try writeData("Library/Saved Application State/com.example.closed.savedState/windows.plist")
        _ = try writeData("Library/Saved Application State/com.example.empty.savedState/windows.plist", bytes: 0)
        _ = try writeData("Library/Saved Application State/ignored_folder/file.bin")

        // --- Subscanner 7: InstallerPackageSubscanner ---
        // Aged .dmg (40 days old), recent .pkg (2 days old), non-installer .zip
        _ = try writeData("Downloads/OldInstaller.dmg", bytes: 65_536, ageSeconds: 40 * 86_400)
        _ = try writeData("Downloads/RecentPackage.pkg", bytes: 65_536, ageSeconds: 2 * 86_400)
        _ = try writeData("Downloads/Archive.zip", bytes: 65_536, ageSeconds: 40 * 86_400)

        let processGuard = RunningProcessGuard(
            runningBundleIdentifiers: ["com.example.running"],
            runningLocalizedAppNames: ["running app"],
            runningProcessExecutables: ["running"]
        )
        let engine = SafetyGuardEngine(processGuard: processGuard, homeDirectoryPath: mockHome.path)
        let catalog = ApplicationMetadataCatalog(homeDirectoryPath: mockHome.path)

        let r1 = ApplicationCacheSubscanner().scan(safetyEngine: engine, appCatalog: catalog)
        XCTAssertGreaterThanOrEqual(r1.candidates.count, 2)

        let r2 = ElectronAndWebAppCacheSubscanner().scan(safetyEngine: engine, appCatalog: catalog)
        XCTAssertTrue(r2.candidates.contains { $0.category == .webAndElectronCaches })
        XCTAssertTrue(r2.candidates.contains { $0.category == .aiAndAgentRuntimes })

        let r3 = DeveloperToolchainSubscanner().scan(safetyEngine: engine, appCatalog: catalog)
        XCTAssertTrue(r3.candidates.contains { $0.category == .aiAndAgentRuntimes })
        XCTAssertTrue(r3.candidates.contains { $0.category == .developerToolchains })
        XCTAssertTrue(r3.candidates.contains { $0.category == .xcodeJunk && $0.itemName.contains("iPhone 16 Pro") })

        let r4 = LogsAndDiagnosticsSubscanner().scan(safetyEngine: engine, appCatalog: catalog)
        XCTAssertGreaterThanOrEqual(r4.candidates.count, 4)

        let r5 = BrowserCacheSubscanner().scan(safetyEngine: engine, appCatalog: catalog)
        XCTAssertGreaterThanOrEqual(r5.candidates.count, 4)

        let r6 = PreferenceAndStateHygieneSubscanner().scan(safetyEngine: engine, appCatalog: catalog)
        XCTAssertEqual(r6.candidates.count, 3, "0-byte plist, corrupt plist, and closed app savedState should be found")

        let r7Default = InstallerPackageSubscanner().scan(safetyEngine: engine, appCatalog: catalog)
        XCTAssertEqual(r7Default.candidates.count, 1, "Only >30 day old .dmg should be included by default")
        XCTAssertEqual(r7Default.skippedProtectedCount, 1, "Recent .pkg (<30 days old) should be skipped")

        let r7All = InstallerPackageSubscanner(minimumAgeDays: 0).scan(safetyEngine: engine, appCatalog: catalog)
        XCTAssertEqual(r7All.candidates.count, 2, "Both .dmg and .pkg should be found when minimumAgeDays == 0")

        // 3. Truncate all non-plist files in mockHome to 0 bytes so DiskAllocatedSizeCalculator returns 0 allocatedBytes
        //    and every subscanner exercises its `guard metrics.allocatedBytes > 0 else { continue / return }` branch
        if let enumerator = FileManager.default.enumerator(
            at: mockHome, includingPropertiesForKeys: [.isRegularFileKey])
        {
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension != "plist",
                    (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                {
                    try? Data().write(to: fileURL)
                }
            }
        }
        for scanner in ScanOrchestrator(homeDirectoryPath: mockHome.path).subscanners {
            _ = scanner.scan(safetyEngine: engine, appCatalog: catalog)
        }
        _ = InstallerPackageSubscanner(minimumAgeDays: 0).scan(safetyEngine: engine, appCatalog: catalog)

        // 4. Move mockHome under a "CloudKit" component (which is in rules.protectedCacheComponents)
        //    and re-run all 7 subscanners to exercise every `!verdict.isAllowed` guard branch
        let blockedParent = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MacSweepBlocked-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: blockedParent) }
        try FileManager.default.createDirectory(at: blockedParent, withIntermediateDirectories: true)
        let blockedHome = blockedParent.appendingPathComponent("CloudKit")
        try FileManager.default.moveItem(at: mockHome, to: blockedHome)
        let blockedEngine = SafetyGuardEngine(
            processGuard: processGuard,
            homeDirectoryPath: blockedHome.path
        )
        for scanner in ScanOrchestrator(homeDirectoryPath: blockedHome.path).subscanners {
            let blockedResult = scanner.scan(safetyEngine: blockedEngine, appCatalog: catalog)
            XCTAssertTrue(blockedResult.candidates.isEmpty)
            XCTAssertGreaterThan(blockedResult.skippedProtectedCount, 0)
        }
        let blockedPkgResult = InstallerPackageSubscanner(minimumAgeDays: 0).scan(
            safetyEngine: blockedEngine,
            appCatalog: catalog
        )
        XCTAssertTrue(blockedPkgResult.candidates.isEmpty)
        XCTAssertGreaterThan(blockedPkgResult.skippedProtectedCount, 0)
    }

    func testLocalizationExhaustiveAllLanguagesAndBranches() {
        // 1. AppLanguage properties & systemDefault branches
        XCTAssertEqual(AppLanguage.systemDefault(preferredLanguages: ["es-MX"]), .spanish)
        XCTAssertEqual(AppLanguage.systemDefault(preferredLanguages: ["fr-CA"]), .french)
        XCTAssertEqual(AppLanguage.systemDefault(preferredLanguages: ["en-US"]), .english)
        XCTAssertEqual(AppLanguage.systemDefault(preferredLanguages: ["de-DE"], fallbackLanguageCode: "es"), .spanish)
        XCTAssertEqual(AppLanguage.systemDefault(preferredLanguages: ["de-DE"], fallbackLanguageCode: "fr"), .french)
        XCTAssertEqual(AppLanguage.systemDefault(preferredLanguages: ["de-DE"], fallbackLanguageCode: "de"), .english)
        XCTAssertEqual(AppLanguage.systemDefault(preferredLanguages: [], fallbackLanguageCode: nil), .english)
        _ = AppLanguage.systemDefault()

        // 2. Path abbreviation branches (real home prefix, /Users/<name> prefix, and non-home path)
        let realHome = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(L10n.abbreviateHomePath(realHome + "/Library/Caches"), "~/Library/Caches")
        XCTAssertEqual(L10n.abbreviateHomePath("/Users/someoneelse/Library/Caches"), "~/Library/Caches")
        XCTAssertEqual(L10n.abbreviateHomePath("/Users/onlytwo"), "~")
        XCTAssertEqual(L10n.abbreviateHomePath("/Users"), "/Users")
        XCTAssertEqual(L10n.abbreviateHomePath("/Library/Caches"), "/Library/Caches")

        // 3. Exhaustively invoke every L10n static method across all 3 languages (.english, .spanish, .french)
        let stages = [
            "Scan complete.",
            "Indexing installed applications...",
            "Launching Application Caches...",
            "Scanning Application Caches...",
            "Completed Application Caches",
            "Aggregating and deduplicating...",
            "Custom unknown stage",
        ]

        for lang in AppLanguage.allCases {
            XCTAssertFalse(lang.id.isEmpty)
            XCTAssertFalse(lang.shortCode.isEmpty)
            XCTAssertFalse(lang.shortLabel.isEmpty)
            XCTAssertFalse(lang.displayName.isEmpty)

            for scope in ScanScope.allCases {
                XCTAssertFalse(L10n.scopeTitle(scope, lang).isEmpty)
                XCTAssertFalse(L10n.scopeShortDescription(scope, lang).isEmpty)
            }
            for cat in CleanupCategory.allCases {
                XCTAssertFalse(L10n.categoryTitle(cat, lang).isEmpty)
                XCTAssertFalse(L10n.categorySubtitle(cat, lang).isEmpty)
            }
            for conf in [SafetyConfidence.safeAutoSelect, .reviewRecommended, .blocked] {
                XCTAssertFalse(L10n.confidenceBadge(conf, lang).isEmpty)
                XCTAssertFalse(L10n.shortConfidenceBadge(conf, lang).isEmpty)
            }
            for filter in ConfidenceFilter.allCases {
                XCTAssertFalse(L10n.confidenceFilterTitle(filter, lang).isEmpty)
            }

            XCTAssertFalse(L10n.welcomeTitle(lang).isEmpty)
            XCTAssertFalse(L10n.welcomeSubtitle(lang).isEmpty)
            XCTAssertFalse(L10n.selectedBadge(lang).isEmpty)
            XCTAssertFalse(L10n.unselectedBadge(lang).isEmpty)
            XCTAssertFalse(L10n.startScanButton(lang).isEmpty)

            XCTAssertFalse(L10n.kpiTotalDiscovered(lang).isEmpty)
            XCTAssertFalse(L10n.kpiGroupsAndFiles(3, "42", lang).isEmpty)
            XCTAssertFalse(L10n.kpiSafeAutoSelected(lang).isEmpty)
            XCTAssertFalse(L10n.kpiRegenerableSub(lang).isEmpty)
            XCTAssertFalse(L10n.kpiOptionalReview(lang).isEmpty)
            XCTAssertFalse(L10n.kpiReviewSub(lang).isEmpty)
            XCTAssertFalse(L10n.kpiSafetyGuards(lang).isEmpty)
            XCTAssertFalse(L10n.kpiGuardedValue(7, lang).isEmpty)
            XCTAssertFalse(L10n.kpiActiveAppsProtected(2, lang).isEmpty)

            XCTAssertFalse(L10n.scopesButtonTitle(2, 3, lang).isEmpty)
            XCTAssertFalse(L10n.rescanButtonTitle(lang).isEmpty)
            XCTAssertFalse(L10n.cleanupDomainsHeader(lang).isEmpty)
            XCTAssertFalse(L10n.activeCountBadge(4, lang).isEmpty)
            XCTAssertFalse(L10n.groupsAndSafeSummary(5, "12 MB", lang).isEmpty)
            XCTAssertFalse(L10n.bundlesCountBadge(6, lang).isEmpty)
            XCTAssertFalse(L10n.filterSearchPlaceholder(lang).isEmpty)
            XCTAssertFalse(L10n.filesCountLabel("10", lang).isEmpty)
            XCTAssertFalse(L10n.targetsCountLabel(3, lang).isEmpty)
            XCTAssertFalse(L10n.selectedOverTotalVolume(lang).isEmpty)
            XCTAssertFalse(L10n.inspectableFilesystemTargets(lang).isEmpty)
            XCTAssertFalse(L10n.revealInFinder(lang).isEmpty)
            XCTAssertFalse(L10n.additionalTargetsHeader("Caches", lang).isEmpty)
            XCTAssertFalse(L10n.clickAnyTargetToInspect(lang).isEmpty)

            XCTAssertFalse(L10n.runningAppBadge(lang).isEmpty)
            XCTAssertFalse(L10n.selectedForPreview(lang).isEmpty)
            XCTAssertFalse(L10n.verifySafetyGuardsDryRun(lang).isEmpty)
            XCTAssertFalse(L10n.statusReadyToScan(lang).isEmpty)
            XCTAssertFalse(L10n.statusScanning(lang).isEmpty)
            XCTAssertFalse(
                L10n.statusCompleted(duration: 0.42, guardedCount: 5, activeScopes: 2, totalScopes: 3, lang: lang)
                    .isEmpty)
            XCTAssertFalse(L10n.footerSelectionStatus(duration: 0.42, selectedCount: 0, lang: lang).isEmpty)
            XCTAssertFalse(L10n.footerSelectionStatus(duration: 0.42, selectedCount: 1, lang: lang).isEmpty)
            XCTAssertFalse(L10n.footerSelectionStatus(duration: 0.42, selectedCount: 4, lang: lang).isEmpty)

            XCTAssertFalse(
                L10n.scanCompletedStatus(
                    language: lang, duration: 0.42, guardedCount: 5, activeScopes: 2, totalScopes: 3
                ).isEmpty)
            XCTAssertFalse(L10n.selectScopesToBegin(lang).isEmpty)
            XCTAssertFalse(L10n.initializingScanStatus(language: lang, scopes: "General, AI").isEmpty)
            XCTAssertFalse(L10n.dryRunVerifiedStatus(language: lang, itemsCount: 3, formattedBytes: "15 MB").isEmpty)
            XCTAssertFalse(L10n.nonDestructivePreviewCaption(lang).isEmpty)
            XCTAssertFalse(L10n.totalDiscoveredTitle(lang).isEmpty)
            XCTAssertFalse(L10n.groupsLabel(lang).isEmpty)
            XCTAssertFalse(L10n.filesLabel(lang).isEmpty)
            XCTAssertFalse(L10n.safeLabel(lang).isEmpty)
            XCTAssertFalse(L10n.safeAutoSelectedTitle(lang).isEmpty)
            XCTAssertFalse(L10n.regenerableCachesSubtitle(lang).isEmpty)
            XCTAssertFalse(L10n.optionalReviewTitle(lang).isEmpty)
            XCTAssertFalse(L10n.simulatorAndBrowsersSubtitle(lang).isEmpty)
            XCTAssertFalse(L10n.safetyGuardsTitle(lang).isEmpty)
            XCTAssertFalse(L10n.guardedWord(lang).isEmpty)
            XCTAssertFalse(L10n.activeAppsProtectedWord(lang).isEmpty)
            XCTAssertFalse(L10n.scopesButton(lang).isEmpty)
            XCTAssertFalse(L10n.scanningButton(lang).isEmpty)
            XCTAssertFalse(L10n.rescanButton(lang).isEmpty)
            XCTAssertFalse(L10n.activeBadge(lang).isEmpty)
            XCTAssertFalse(L10n.scanningFilesystemLabel(lang).isEmpty)
            XCTAssertFalse(L10n.bundlesLabel(lang).isEmpty)
            XCTAssertFalse(L10n.filterPlaceholder(lang).isEmpty)
            XCTAssertFalse(L10n.selectCleanupDomainLabel(lang).isEmpty)
            XCTAssertFalse(L10n.runningProcessGuardedLabel(lang).isEmpty)
            XCTAssertFalse(L10n.targetsWord(lang).isEmpty)
            XCTAssertFalse(L10n.selectedTotalVolumeHeader(lang).isEmpty)
            XCTAssertFalse(L10n.inspectableTargetsHeader(lang).isEmpty)
            XCTAssertFalse(L10n.additionalTargetsHeader(lang).isEmpty)
            XCTAssertFalse(L10n.clickToInspectLabel(lang).isEmpty)
            XCTAssertFalse(L10n.selectBundleLabel(lang).isEmpty)
            XCTAssertFalse(L10n.revealInFinderButton(lang).isEmpty)
            XCTAssertFalse(L10n.posixHeuristicBadge(lang).isEmpty)
            XCTAssertFalse(L10n.ruleEngineBadge(lang).isEmpty)
            XCTAssertFalse(L10n.selectedForPreviewLabel(lang).isEmpty)
            XCTAssertFalse(L10n.verifyDryRunButton(lang).isEmpty)

            XCTAssertFalse(L10n.summaryTotalLabel(lang).isEmpty)
            XCTAssertFalse(L10n.summarySafeLabel(lang).isEmpty)
            XCTAssertFalse(L10n.summaryReviewLabel(lang).isEmpty)
            XCTAssertFalse(L10n.unselectReviewButton(lang).isEmpty)
            XCTAssertFalse(L10n.noMatchingFilterItemsLabel(.safeOnly, lang).isEmpty)
            XCTAssertFalse(L10n.noMatchingFilterItemsLabel(.needsReview, lang).isEmpty)
            XCTAssertFalse(L10n.noMatchingFilterItemsLabel(.all, lang).isEmpty)
            XCTAssertFalse(L10n.showAllItemsButton(lang).isEmpty)
            XCTAssertFalse(L10n.itemsCountBadge(1, lang).isEmpty)
            XCTAssertFalse(L10n.itemsCountBadge(4, lang).isEmpty)
            XCTAssertFalse(L10n.selectedOfTotalSummary("10 MB", "10 MB", lang).isEmpty)
            XCTAssertFalse(L10n.selectedOfTotalSummary("5 MB", "10 MB", lang).isEmpty)
            XCTAssertFalse(L10n.cleanFilterPlaceholder(lang).isEmpty)

            XCTAssertFalse(L10n.scanningInProgressTitle(lang).isEmpty)
            XCTAssertFalse(L10n.scanningInProgressSubtitle(lang).isEmpty)
            XCTAssertFalse(L10n.scanningElapsedBadge(seconds: 2.5, language: lang).isEmpty)

            for stage in stages {
                XCTAssertFalse(L10n.localizedProgressStage(stage, language: lang).isEmpty)
            }

            XCTAssertFalse(L10n.cleanSelectedButtonTitle(count: 0, formattedBytes: "0 B", language: lang).isEmpty)
            XCTAssertFalse(L10n.cleanSelectedButtonTitle(count: 3, formattedBytes: "15 MB", language: lang).isEmpty)
            XCTAssertFalse(L10n.cleaningInProgressTitle(lang).isEmpty)
            XCTAssertFalse(L10n.cleaningInProgressSubtitle(lang).isEmpty)
            XCTAssertFalse(L10n.cleaningCurrentItemLabel(lang).isEmpty)
            XCTAssertFalse(L10n.cleaningGuardPillTrash(lang).isEmpty)
            XCTAssertFalse(L10n.cleaningGuardPillProtected(lang).isEmpty)

            XCTAssertFalse(
                L10n.cleanupCompletedStatus(
                    language: lang,
                    movedCount: 4,
                    formattedBytes: "10 MB",
                    skippedCount: 0,
                    errorCount: 0
                ).isEmpty
            )
            XCTAssertFalse(
                L10n.cleanupCompletedStatus(
                    language: lang,
                    movedCount: 4,
                    formattedBytes: "10 MB",
                    skippedCount: 2,
                    errorCount: 1
                ).isEmpty
            )

            XCTAssertFalse(L10n.runningAppsModalTitle(count: 1, language: lang).isEmpty)
            XCTAssertFalse(L10n.runningAppsModalTitle(count: 3, language: lang).isEmpty)
            XCTAssertFalse(L10n.runningAppsModalSubtitle(lang).isEmpty)
            XCTAssertFalse(L10n.runningAppsQuitAndCleanButton(lang).isEmpty)
            XCTAssertFalse(L10n.runningAppsSkipButton(lang).isEmpty)
            XCTAssertFalse(L10n.runningAppsCleanAnywayButton(lang).isEmpty)
            XCTAssertFalse(L10n.runningAppsCancelButton(lang).isEmpty)
            XCTAssertFalse(L10n.runningAppsClosingProgress(lang).isEmpty)
            XCTAssertFalse(
                L10n.runningAppAffectedSummary(itemsCount: 1, formattedBytes: "4 MB", language: lang).isEmpty)
            XCTAssertFalse(
                L10n.runningAppAffectedSummary(itemsCount: 3, formattedBytes: "12 MB", language: lang).isEmpty)

            XCTAssertFalse(L10n.fullDiskAccessGrantedBadge(lang).isEmpty)
            XCTAssertFalse(L10n.fullDiskAccessOptionalPrompt(lang).isEmpty)
            XCTAssertFalse(L10n.fullDiskAccessTooltip(lang).isEmpty)
        }
    }
}
