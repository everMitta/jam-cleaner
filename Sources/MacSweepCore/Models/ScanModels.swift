import Foundation

/// High-level user-selectable inspection scopes presented on the Pre-Scan Launch Screen.
public enum ScanScope: String, CaseIterable, Codable, Sendable, Identifiable {
    case general = "General"
    case developer = "Developer"
    case ai = "AI"

    public var id: String { rawValue }

    public var title: String {
        title(in: .english)
    }

    public func title(in language: AppLanguage) -> String {
        L10n.scopeTitle(self, language)
    }

    public var shortDescription: String {
        shortDescription(in: .english)
    }

    public func shortDescription(in language: AppLanguage) -> String {
        L10n.scopeShortDescription(self, language)
    }

    public var subtitle: String {
        switch self {
        case .general: return "System, Apps & Browsers"
        case .developer: return "Xcode, Simulators & Toolchains"
        case .ai: return "AI Assistants, Agent Sandboxes & MCP"
        }
    }

    public var systemSymbolName: String {
        switch self {
        case .general: return "sparkles.rectangle.stack.fill"
        case .developer: return "hammer.fill"
        case .ai: return "brain.head.profile"
        }
    }

    public var description: String {
        switch self {
        case .general:
            return
                "Everyday macOS maintenance across user & sandbox application caches, multi-profile web browser caches, desktop Electron apps, rotational system logs, corrupted .plist preferences, and aged disk images."
        case .developer:
            return
                "Deep engineering workspace cleanup for Xcode DerivedData build artifacts, iOS/watchOS DeviceSupport debug symbols, CoreSimulator internal caches, IDE bytecode caches, and compiler/package caches."
        case .ai:
            return
                "Specialized cleanup for local AI desktop assistants, autonomous coding agent runtime sandboxes, MCP headless browser automation profiles, and local WebGPU/shader caches."
        }
    }

    public var highlightBadges: [String] {
        switch self {
        case .general:
            return ["App & Sandbox Caches", "Safari & Chrome", "Electron Apps", "System & Crash Logs", "Saved States"]
        case .developer:
            return ["Xcode DerivedData", "iOS Simulators", "Go & Dart/Flutter", "uv & npm Caches", "VS Code & Brew"]
        case .ai:
            return ["Claude Desktop", "Antigravity IDE", "codex-runtimes", "Chrome DevTools MCP", "Puppeteer & LLM"]
        }
    }

    public var safetyNote: String {
        switch self {
        case .general:
            return
                "Protects iCloud Drive, Keychains, personal ~/Downloads documents, browser cookies/logins, and active app sessions."
        case .developer:
            return
                "Separates safe iOS Simulator internal caches from installed test apps (Runner.app) & guards ~/.ssh, ~/.aws, and IDE settings."
        case .ai:
            return
                "Strictly protects Apple Neural Engine compiled ML models (e5bundlecache) and ~/.claude, ~/.gemini, ~/.agents configurations."
        }
    }

    public var includedCategories: [CleanupCategory] {
        CleanupCategory.allCases.filter { $0.scope == self }
    }
}

/// High-level functional categories for reclaimable system and application storage.
public enum CleanupCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case applicationCaches = "Application Caches"
    case webAndElectronCaches = "Electron & Web App Caches"
    case developerToolchains = "Developer & Toolchain Caches"
    case xcodeJunk = "Xcode & Simulator Data"
    case aiAndAgentRuntimes = "AI & Agent Runtime Caches"
    case logsAndDiagnostics = "Logs & Diagnostic Reports"
    case browserCaches = "Browser Caches"
    case preferenceAndStateHygiene = "Broken Preferences & Saved States"
    case installerPackages = "Aged Disk Images & Installers"

    public var id: String { rawValue }

    public var scope: ScanScope {
        switch self {
        case .applicationCaches,
            .webAndElectronCaches,
            .logsAndDiagnostics,
            .browserCaches,
            .preferenceAndStateHygiene,
            .installerPackages:
            return .general
        case .developerToolchains,
            .xcodeJunk:
            return .developer
        case .aiAndAgentRuntimes:
            return .ai
        }
    }

    public var systemSymbolName: String {
        switch self {
        case .applicationCaches: return "internaldrive.fill"
        case .webAndElectronCaches: return "sparkles.rectangle.stack.fill"
        case .developerToolchains: return "hammer.fill"
        case .xcodeJunk: return "wrench.and.screwdriver.fill"
        case .aiAndAgentRuntimes: return "brain.head.profile"
        case .logsAndDiagnostics: return "doc.text.magnifyingglass"
        case .browserCaches: return "globe"
        case .preferenceAndStateHygiene: return "slider.horizontal.3"
        case .installerPackages: return "opticaldiscdrive.fill"
        }
    }

    public var subtitle: String {
        subtitle(in: .english)
    }

    public func title(in language: AppLanguage) -> String {
        L10n.categoryTitle(self, language)
    }

    public func subtitle(in language: AppLanguage) -> String {
        L10n.categorySubtitle(self, language)
    }
}

/// Classification produced by the safety guard pipeline indicating whether an item is safe to auto-select.
public enum SafetyConfidence: String, Codable, Sendable, Comparable {
    /// 100% regenerable cache or log file; safe to select by default.
    case safeAutoSelect = "Safe (Auto-Selected)"
    /// Reclaimable item that warrants user confirmation (e.g., aged installers, simulator devices, or currently running app caches).
    case reviewRecommended = "Review Recommended"
    /// Hard-blocked by safety guards; never surfaced for deletion.
    case blocked = "Blocked by Safety Guard"

    public func badgeTitle(in language: AppLanguage) -> String {
        L10n.confidenceBadge(self, language)
    }

    private var sortOrder: Int {
        switch self {
        case .safeAutoSelect: return 0
        case .reviewRecommended: return 1
        case .blocked: return 2
        }
    }

    public static func < (lhs: SafetyConfidence, rhs: SafetyConfidence) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

/// Interactive filter for viewing All items, Safe items only, or Needs Review items only.
public enum ConfidenceFilter: String, CaseIterable, Codable, Sendable, Identifiable {
    case all = "All"
    case safeOnly = "Safe"
    case needsReview = "Needs Review"

    public var id: String { rawValue }

    public func matches(_ confidence: SafetyConfidence) -> Bool {
        switch self {
        case .all:
            return true
        case .safeOnly:
            return confidence == .safeAutoSelect
        case .needsReview:
            return confidence == .reviewRecommended
        }
    }

    public func title(in language: AppLanguage) -> String {
        L10n.confidenceFilterTitle(self, language)
    }

    public var systemSymbolName: String {
        switch self {
        case .all:
            return "square.stack.3d.up"
        case .safeOnly:
            return "checkmark.shield.fill"
        case .needsReview:
            return "exclamationmark.triangle.fill"
        }
    }
}

/// Level 3 Leaf Node: A concrete file or directory subtree evaluated as a cleanup candidate.
public struct ScanCandidateItem: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let path: String
    public let category: CleanupCategory
    public let bundleIdentifier: String
    public let appDisplayName: String
    public let itemName: String
    public let allocatedBytes: UInt64
    public let fileCount: Int
    public let lastModified: Date?
    public let confidence: SafetyConfidence
    public let isRunningApp: Bool
    public let ruleIdentifier: String
    public let safetyExplanation: String
    public var isSelected: Bool

    public init(
        path: String,
        category: CleanupCategory,
        bundleIdentifier: String,
        appDisplayName: String,
        itemName: String,
        allocatedBytes: UInt64,
        fileCount: Int,
        lastModified: Date?,
        confidence: SafetyConfidence,
        isRunningApp: Bool,
        ruleIdentifier: String,
        safetyExplanation: String,
        isSelected: Bool? = nil
    ) {
        self.id = path
        self.path = path
        self.category = category
        self.bundleIdentifier = bundleIdentifier
        self.appDisplayName = appDisplayName
        self.itemName = itemName
        self.allocatedBytes = allocatedBytes
        self.fileCount = fileCount
        self.lastModified = lastModified
        self.confidence = confidence
        self.isRunningApp = isRunningApp
        self.ruleIdentifier = ruleIdentifier
        self.safetyExplanation = safetyExplanation
        if let explicitSelection = isSelected {
            self.isSelected = explicitSelection
        } else {
            self.isSelected = (confidence == .safeAutoSelect)
        }
    }
}

/// Level 2 Intermediate Node: Groups candidate items belonging to the same application, bundle, or toolchain.
public struct ApplicationBundleGroup: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let category: CleanupCategory
    public let bundleIdentifier: String
    public let appDisplayName: String
    public let bundlePath: String?
    public let isRunning: Bool
    public var items: [ScanCandidateItem]

    public var totalAllocatedBytes: UInt64 {
        items.reduce(0) { $0 + $1.allocatedBytes }
    }

    public var selectedAllocatedBytes: UInt64 {
        items.filter(\.isSelected).reduce(0) { $0 + $1.allocatedBytes }
    }

    public var safeAutoSelectBytes: UInt64 {
        items.filter { $0.confidence == .safeAutoSelect }.reduce(0) { $0 + $1.allocatedBytes }
    }

    public var totalFileCount: Int {
        items.reduce(0) { $0 + $1.fileCount }
    }

    public var isAllSelected: Bool {
        !items.isEmpty && items.allSatisfy(\.isSelected)
    }

    public var isPartiallySelected: Bool {
        let selectedCount = items.filter(\.isSelected).count
        return selectedCount > 0 && selectedCount < items.count
    }

    public var primaryConfidence: SafetyConfidence {
        if items.contains(where: { $0.confidence == .reviewRecommended }) {
            return .reviewRecommended
        }
        return items.first?.confidence ?? .safeAutoSelect
    }

    public func matches(confidenceFilter: ConfidenceFilter) -> Bool {
        switch confidenceFilter {
        case .all:
            return true
        case .safeOnly:
            return items.contains { $0.confidence == .safeAutoSelect }
        case .needsReview:
            return items.contains { $0.confidence == .reviewRecommended }
        }
    }

    public var selectedReviewItemCount: Int {
        items.filter { $0.confidence == .reviewRecommended && $0.isSelected }.count
    }

    public var selectedItemCount: Int {
        items.filter(\.isSelected).count
    }

    public var selectedReviewBytes: UInt64 {
        items.filter { $0.confidence == .reviewRecommended && $0.isSelected }.reduce(0) { $0 + $1.allocatedBytes }
    }

    public init(
        category: CleanupCategory,
        bundleIdentifier: String,
        appDisplayName: String,
        bundlePath: String?,
        isRunning: Bool,
        items: [ScanCandidateItem]
    ) {
        self.id = "\(category.rawValue)::\(bundleIdentifier)"
        self.category = category
        self.bundleIdentifier = bundleIdentifier
        self.appDisplayName = appDisplayName
        self.bundlePath = bundlePath
        self.isRunning = isRunning
        self.items = items.sorted { $0.allocatedBytes > $1.allocatedBytes }
    }
}

/// Level 1 Top-Level Node: Rolls up all application/tool groups within a cleanup category.
public struct CleanupCategoryGroup: Identifiable, Codable, Sendable, Hashable {
    public var id: String { category.rawValue }
    public let category: CleanupCategory
    public var appGroups: [ApplicationBundleGroup]

    public var totalAllocatedBytes: UInt64 {
        appGroups.reduce(0) { $0 + $1.totalAllocatedBytes }
    }

    public var selectedAllocatedBytes: UInt64 {
        appGroups.reduce(0) { $0 + $1.selectedAllocatedBytes }
    }

    public var safeAutoSelectBytes: UInt64 {
        appGroups.reduce(0) { $0 + $1.safeAutoSelectBytes }
    }

    public var reviewRecommendedBytes: UInt64 {
        totalAllocatedBytes - min(totalAllocatedBytes, safeAutoSelectBytes)
    }

    public var totalItemCount: Int {
        appGroups.reduce(0) { $0 + $1.items.count }
    }

    public var totalFileCount: Int {
        appGroups.reduce(0) { $0 + $1.totalFileCount }
    }

    public var isAllSelected: Bool {
        !appGroups.isEmpty && appGroups.allSatisfy(\.isAllSelected)
    }

    public var isPartiallySelected: Bool {
        let hasAnySelected = appGroups.contains { $0.isAllSelected || $0.isPartiallySelected }
        return hasAnySelected && !isAllSelected
    }

    public func appGroups(matching filter: ConfidenceFilter) -> [ApplicationBundleGroup] {
        appGroups.filter { $0.matches(confidenceFilter: filter) }
    }

    public func appGroupCount(matching filter: ConfidenceFilter) -> Int {
        appGroups(matching: filter).count
    }

    public var reviewAppGroupCount: Int {
        appGroupCount(matching: .needsReview)
    }

    public var safeAppGroupCount: Int {
        appGroupCount(matching: .safeOnly)
    }

    public var selectedReviewItemCount: Int {
        appGroups.reduce(0) { $0 + $1.selectedReviewItemCount }
    }

    public var selectedItemCount: Int {
        appGroups.reduce(0) { $0 + $1.selectedItemCount }
    }

    public var selectedReviewBytes: UInt64 {
        appGroups.reduce(0) { $0 + $1.selectedReviewBytes }
    }

    public init(category: CleanupCategory, appGroups: [ApplicationBundleGroup]) {
        self.category = category
        self.appGroups = appGroups.sorted { $0.totalAllocatedBytes > $1.totalAllocatedBytes }
    }
}

/// Complete snapshot of a full MacSweep scan session.
public struct ScanReport: Codable, Sendable {
    public let generatedAt: Date
    public let scanDurationSeconds: Double
    public var categories: [CleanupCategoryGroup]
    public let protectedPathsSkippedCount: Int
    public let runningAppsDetectedCount: Int

    public var grandTotalBytes: UInt64 {
        categories.reduce(0) { $0 + $1.totalAllocatedBytes }
    }

    public var selectedTotalBytes: UInt64 {
        categories.reduce(0) { $0 + $1.selectedAllocatedBytes }
    }

    public var safeAutoSelectedBytes: UInt64 {
        categories.reduce(0) { $0 + $1.safeAutoSelectBytes }
    }

    public var reviewRecommendedBytes: UInt64 {
        categories.reduce(0) { $0 + $1.reviewRecommendedBytes }
    }

    public var totalCandidateCount: Int {
        categories.reduce(0) { $0 + $1.totalItemCount }
    }

    public var totalSelectedCount: Int {
        categories.reduce(0) { $0 + $1.selectedItemCount }
    }

    public var totalFileCount: Int {
        categories.reduce(0) { $0 + $1.totalFileCount }
    }

    public var selectedReviewItemCount: Int {
        categories.reduce(0) { $0 + $1.selectedReviewItemCount }
    }

    public var selectedReviewBytes: UInt64 {
        categories.reduce(0) { $0 + $1.selectedReviewBytes }
    }

    public func appGroupCount(matching filter: ConfidenceFilter) -> Int {
        categories.reduce(0) { $0 + $1.appGroupCount(matching: filter) }
    }

    public func categories(for scope: ScanScope) -> [CleanupCategoryGroup] {
        categories.filter { $0.category.scope == scope }
    }

    public func totalAllocatedBytes(for scope: ScanScope) -> UInt64 {
        categories(for: scope).reduce(0) { $0 + $1.totalAllocatedBytes }
    }

    public func selectedAllocatedBytes(for scope: ScanScope) -> UInt64 {
        categories(for: scope).reduce(0) { $0 + $1.selectedAllocatedBytes }
    }

    public func isScopeAllSelected(_ scope: ScanScope) -> Bool {
        let scoped = categories(for: scope)
        return !scoped.isEmpty && scoped.allSatisfy(\.isAllSelected)
    }

    public func isScopePartiallySelected(_ scope: ScanScope) -> Bool {
        let scoped = categories(for: scope)
        let hasAny = scoped.contains { $0.isAllSelected || $0.isPartiallySelected }
        return hasAny && !isScopeAllSelected(scope)
    }

    public init(
        generatedAt: Date = Date(),
        scanDurationSeconds: Double,
        categories: [CleanupCategoryGroup],
        protectedPathsSkippedCount: Int,
        runningAppsDetectedCount: Int
    ) {
        self.generatedAt = generatedAt
        self.scanDurationSeconds = scanDurationSeconds
        self.categories = categories
        self.protectedPathsSkippedCount = protectedPathsSkippedCount
        self.runningAppsDetectedCount = runningAppsDetectedCount
    }

    /// Ensures any legacy cached report that predates `.aiAndAgentRuntimes` automatically promotes
    /// AI & Agent runtime groups (Claude, Antigravity, codex-runtimes, chrome-devtools-mcp, Puppeteer, etc.)
    /// into the dedicated `.aiAndAgentRuntimes` category.
    public func upgradedWithAICategory() -> ScanReport {
        if categories.contains(where: { $0.category == .aiAndAgentRuntimes }) {
            return self
        }

        let aiTokens: Set<String> = [
            "com.anthropic.claudefordesktop",
            "claude",
            "antigravity",
            "com.google.antigravity",
            "io.sandbox.codex-runtimes",
            "org.chromium.devtools-mcp",
            "dev.pptr.puppeteer",
            "co.huggingface.cache",
            "com.todesktop.230313mzl4w4u92",
            "cursor",
            "windsurf",
            "com.openai.chat",
        ]

        func isAIGroup(_ group: ApplicationBundleGroup) -> Bool {
            let lowerBundle = group.bundleIdentifier.lowercased()
            let lowerName = group.appDisplayName.lowercased()
            if aiTokens.contains(lowerBundle) || aiTokens.contains(lowerName) {
                return true
            }
            return lowerBundle.contains("claude")
                || lowerBundle.contains("antigravity")
                || lowerBundle.contains("codex-runtimes")
                || lowerBundle.contains("devtools-mcp")
                || lowerBundle.contains("puppeteer")
                || lowerBundle.contains("huggingface")
                || lowerName.contains("claude")
                || lowerName.contains("antigravity")
                || lowerName.contains("codex-runtimes")
                || lowerName.contains("devtools automation")
                || lowerName.contains("puppeteer")
        }

        var updatedCategories: [CleanupCategoryGroup] = []
        var promotedAIGroups: [ApplicationBundleGroup] = []

        for categoryGroup in categories {
            if categoryGroup.category == .developerToolchains || categoryGroup.category == .webAndElectronCaches {
                var remaining: [ApplicationBundleGroup] = []
                for group in categoryGroup.appGroups {
                    if isAIGroup(group) {
                        let reboundItems = group.items.map { item in
                            ScanCandidateItem(
                                path: item.path,
                                category: .aiAndAgentRuntimes,
                                bundleIdentifier: item.bundleIdentifier,
                                appDisplayName: item.appDisplayName,
                                itemName: item.itemName,
                                allocatedBytes: item.allocatedBytes,
                                fileCount: item.fileCount,
                                lastModified: item.lastModified,
                                confidence: item.confidence,
                                isRunningApp: item.isRunningApp,
                                ruleIdentifier: item.ruleIdentifier,
                                safetyExplanation: item.safetyExplanation,
                                isSelected: item.isSelected
                            )
                        }
                        promotedAIGroups.append(
                            ApplicationBundleGroup(
                                category: .aiAndAgentRuntimes,
                                bundleIdentifier: group.bundleIdentifier,
                                appDisplayName: group.appDisplayName,
                                bundlePath: group.bundlePath,
                                isRunning: group.isRunning,
                                items: reboundItems
                            )
                        )
                    } else {
                        remaining.append(group)
                    }
                }
                if !remaining.isEmpty {
                    updatedCategories.append(
                        CleanupCategoryGroup(category: categoryGroup.category, appGroups: remaining)
                    )
                }
            } else {
                updatedCategories.append(categoryGroup)
            }
        }

        if !promotedAIGroups.isEmpty {
            updatedCategories.append(
                CleanupCategoryGroup(category: .aiAndAgentRuntimes, appGroups: promotedAIGroups)
            )
            updatedCategories.sort { $0.totalAllocatedBytes > $1.totalAllocatedBytes }
        }

        return ScanReport(
            generatedAt: generatedAt,
            scanDurationSeconds: scanDurationSeconds,
            categories: updatedCategories,
            protectedPathsSkippedCount: protectedPathsSkippedCount,
            runningAppsDetectedCount: runningAppsDetectedCount
        )
    }

    /// Returns a copy of the report containing only categories belonging to the specified `ScanScope` set.
    public func filtered(by scopes: Set<ScanScope>) -> ScanReport {
        let normalized = upgradedWithAICategory()
        guard scopes.count < ScanScope.allCases.count else {
            return normalized
        }
        let scopedCategories = normalized.categories.filter { scopes.contains($0.category.scope) }
        return ScanReport(
            generatedAt: normalized.generatedAt,
            scanDurationSeconds: normalized.scanDurationSeconds,
            categories: scopedCategories,
            protectedPathsSkippedCount: normalized.protectedPathsSkippedCount,
            runningAppsDetectedCount: normalized.runningAppsDetectedCount
        )
    }

    /// Total bytes discovered within a specific `ScanScope`.
    public func totalBytes(for scope: ScanScope) -> UInt64 {
        let normalized = upgradedWithAICategory()
        return normalized.categories
            .filter { $0.category.scope == scope }
            .reduce(0) { $0 + $1.totalAllocatedBytes }
    }

    /// Returns a new `ScanReport` with all items whose IDs are in `removedIDs` pruned out,
    /// automatically dropping empty application groups and empty categories.
    public func removingItems(withIDs removedIDs: Set<String>) -> ScanReport {
        guard !removedIDs.isEmpty else { return self }
        var updatedCategories: [CleanupCategoryGroup] = []
        for categoryGroup in categories {
            var updatedGroups: [ApplicationBundleGroup] = []
            for group in categoryGroup.appGroups {
                let remainingItems = group.items.filter { !removedIDs.contains($0.id) }
                if !remainingItems.isEmpty {
                    updatedGroups.append(
                        ApplicationBundleGroup(
                            category: group.category,
                            bundleIdentifier: group.bundleIdentifier,
                            appDisplayName: group.appDisplayName,
                            bundlePath: group.bundlePath,
                            isRunning: group.isRunning,
                            items: remainingItems
                        )
                    )
                }
            }
            if !updatedGroups.isEmpty {
                updatedCategories.append(
                    CleanupCategoryGroup(
                        category: categoryGroup.category,
                        appGroups: updatedGroups
                    )
                )
            }
        }
        updatedCategories.sort { $0.totalAllocatedBytes > $1.totalAllocatedBytes }
        return ScanReport(
            generatedAt: generatedAt,
            scanDurationSeconds: scanDurationSeconds,
            categories: updatedCategories,
            protectedPathsSkippedCount: protectedPathsSkippedCount,
            runningAppsDetectedCount: runningAppsDetectedCount
        )
    }
}

/// Byte formatting helper using standard decimal/binary human-readable units.
public enum ByteFormatter {
    public static func string(from bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        return formatter.string(fromByteCount: Int64(clamping: bytes))
    }
}
