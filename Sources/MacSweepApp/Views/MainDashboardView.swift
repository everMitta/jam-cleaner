import AppKit
import Foundation
import MacSweepCore
import SwiftUI

@MainActor
public final class ScanViewModel: ObservableObject {
    @Published public var report: ScanReport?
    private var unfilteredReport: ScanReport?
    @Published public var selectedScopes: Set<ScanScope> = Set(ScanScope.allCases)
    @Published public var isShowingScopeSelector: Bool
    @Published public var isScanning: Bool = false
    @Published public var scanProgress: Double = 0.0
    @Published public var scanElapsedSeconds: Double = 0.0
    @Published public var isCleaning: Bool = false
    @Published public var cleaningProgress: Double = 0.0
    @Published public var cleaningElapsedSeconds: Double = 0.0
    @Published public var cleaningCurrentItemText: String = ""
    @Published public var cleaningTargetCount: Int = 0
    @Published public var cleaningTargetBytes: UInt64 = 0
    @Published public var pendingRunningAppConflicts: [RunningApplicationConflict] = []
    @Published public var isQuittingRunningApps: Bool = false
    @Published public var hasFullDiskAccess: Bool = FullDiskAccessPermissionHelper.hasFullDiskAccess()
    @Published public var language: AppLanguage
    @Published public var statusMessage: String
    @Published public var selectedCategoryID: String?
    @Published public var selectedAppGroupID: String?
    @Published public var searchQuery: String = ""
    @Published public var confidenceFilter: ConfidenceFilter = .all
    @Published public var lastDryRunSummary: String?

    private let orchestrator = ScanOrchestrator()
    private var orchestratorTargetProgress: Double = 0.06
    private var rawProgressStageMessage: String = ""
    private var progressTimer: Timer?
    private var cleaningTargetProgress: Double = 0.10
    private var cleaningTimer: Timer?

    public init(
        initialReport: ScanReport? = nil,
        showScopeSelectorInitially: Bool? = nil,
        initialLanguage: AppLanguage? = nil,
        simulateScanningState: Bool = false,
        simulateCleaningState: Bool = false
    ) {
        let resolvedLanguage = initialLanguage ?? AppLanguage.systemDefault()
        self.language = resolvedLanguage

        if simulateCleaningState {
            self.isShowingScopeSelector = false
            self.isCleaning = true
            self.cleaningProgress = 0.72
            self.cleaningElapsedSeconds = 0.8
            self.cleaningTargetCount = 3
            self.cleaningTargetBytes = 148_900_000
            self.cleaningCurrentItemText = "Safari — com.apple.Safari"
            self.statusMessage = L10n.cleaningInProgressTitle(resolvedLanguage)
        } else if simulateScanningState {
            self.isShowingScopeSelector = false
            self.isScanning = true
            self.scanProgress = 0.64
            self.scanElapsedSeconds = 6.8
            self.rawProgressStageMessage = "Completed Developer Caches"
            self.statusMessage = L10n.localizedProgressStage("Completed Developer Caches", language: resolvedLanguage)
        } else if let initialReport {
            let upgraded = initialReport.upgradedWithAICategory()
            self.unfilteredReport = upgraded
            let scoped = upgraded.filtered(by: Set(ScanScope.allCases))
            self.report = scoped
            self.selectedCategoryID = scoped.categories.first?.id
            self.selectedAppGroupID = scoped.categories.first?.appGroups.first?.id
            self.isShowingScopeSelector = showScopeSelectorInitially ?? false
            self.scanProgress = 1.0
            self.scanElapsedSeconds = scoped.scanDurationSeconds
            self.statusMessage = L10n.scanCompletedStatus(
                language: resolvedLanguage,
                duration: scoped.scanDurationSeconds,
                guardedCount: scoped.protectedPathsSkippedCount,
                activeScopes: ScanScope.allCases.count,
                totalScopes: ScanScope.allCases.count
            )
        } else {
            // Main opening screen: do NOT scan or preload any report until the user clicks Start Scan
            self.isShowingScopeSelector = showScopeSelectorInitially ?? true
            self.statusMessage = L10n.selectScopesToBegin(resolvedLanguage)
        }
    }

    public func setLanguage(_ newLanguage: AppLanguage) {
        withAnimation(InnotecTheme.fluidSpring) {
            self.language = newLanguage
            if isScanning {
                if !rawProgressStageMessage.isEmpty {
                    self.statusMessage = L10n.localizedProgressStage(rawProgressStageMessage, language: newLanguage)
                } else {
                    let scopeTitles = selectedScopes.map { $0.title(in: newLanguage) }.sorted().joined(separator: ", ")
                    self.statusMessage = L10n.initializingScanStatus(language: newLanguage, scopes: scopeTitles)
                }
            } else if let report {
                self.statusMessage = L10n.scanCompletedStatus(
                    language: newLanguage,
                    duration: report.scanDurationSeconds,
                    guardedCount: report.protectedPathsSkippedCount,
                    activeScopes: selectedScopes.count,
                    totalScopes: ScanScope.allCases.count
                )
            } else {
                self.statusMessage = L10n.selectScopesToBegin(newLanguage)
            }
        }
    }

    public func toggleScope(_ scope: ScanScope) {
        withAnimation(InnotecTheme.fluidSpring) {
            if selectedScopes.contains(scope) {
                if selectedScopes.count > 1 {
                    selectedScopes.remove(scope)
                }
            } else {
                selectedScopes.insert(scope)
            }
            if let unfilteredReport {
                let scoped = unfilteredReport.filtered(by: selectedScopes)
                self.report = scoped
                self.selectedCategoryID = scoped.categories.first?.id
                self.selectedAppGroupID = scoped.categories.first?.appGroups.first?.id
            }
        }
    }

    public func startScopedScan(forceFresh: Bool = true) {
        guard !selectedScopes.isEmpty else { return }
        hasFullDiskAccess = FullDiskAccessPermissionHelper.hasFullDiskAccess()
        withAnimation(InnotecTheme.fluidSpring) {
            isShowingScopeSelector = false
        }
        performScan(forceFresh: forceFresh)
    }

    public func refreshFullDiskAccessStatus() {
        hasFullDiskAccess = FullDiskAccessPermissionHelper.hasFullDiskAccess()
    }

    public func openFullDiskAccessSettings() {
        _ = FullDiskAccessPermissionHelper.openSystemSettingsFullDiskAccess()
    }

    public func performScan(forceFresh: Bool = false) {
        guard !isScanning else { return }

        if !forceFresh {
            if let existingUnfiltered = unfilteredReport {
                let scoped = existingUnfiltered.filtered(by: selectedScopes)
                withAnimation(InnotecTheme.fluidSpring) {
                    self.report = scoped
                    self.selectedCategoryID = scoped.categories.first?.id
                    self.selectedAppGroupID = scoped.categories.first?.appGroups.first?.id
                    self.statusMessage = L10n.scanCompletedStatus(
                        language: language,
                        duration: scoped.scanDurationSeconds,
                        guardedCount: scoped.protectedPathsSkippedCount,
                        activeScopes: selectedScopes.count,
                        totalScopes: ScanScope.allCases.count
                    )
                }
                return
            }

            if let previewPath = ProcessInfo.processInfo.environment["MACSWEEP_PREVIEW_JSON"],
                !previewPath.isEmpty,
                let data = try? Data(contentsOf: URL(fileURLWithPath: previewPath))
            {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let cachedReport = try? decoder.decode(ScanReport.self, from: data) {
                    let upgraded = cachedReport.upgradedWithAICategory()
                    self.unfilteredReport = upgraded
                    let scoped = upgraded.filtered(by: selectedScopes)
                    self.report = scoped
                    self.selectedCategoryID = scoped.categories.first?.id
                    self.selectedAppGroupID = scoped.categories.first?.appGroups.first?.id
                    self.statusMessage = L10n.scanCompletedStatus(
                        language: language,
                        duration: scoped.scanDurationSeconds,
                        guardedCount: scoped.protectedPathsSkippedCount,
                        activeScopes: selectedScopes.count,
                        totalScopes: ScanScope.allCases.count
                    )
                    return
                }
            }
        }

        let activeScopes = selectedScopes
        let currentLang = language
        let scopeTitles = activeScopes.map { $0.title(in: currentLang) }.sorted().joined(separator: ", ")

        // Reset progress counters outside spring animation so a subsequent scan starts cleanly at 0%
        progressTimer?.invalidate()
        scanProgress = 0.0
        scanElapsedSeconds = 0.0
        orchestratorTargetProgress = 0.04
        rawProgressStageMessage = ""
        statusMessage = L10n.initializingScanStatus(language: currentLang, scopes: scopeTitles)
        lastDryRunSummary = nil

        withAnimation(InnotecTheme.fluidSpring) {
            isScanning = true
        }

        let scanStartTime = Date()
        let minVisualDuration: Double = 0.90
        let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, self.isScanning else {
                    t.invalidate()
                    return
                }
                let elapsed = Date().timeIntervalSince(scanStartTime)
                self.scanElapsedSeconds = elapsed
                let visualEnvelope = min(0.96, (elapsed / minVisualDuration) * 0.96)
                let creepCeiling = min(0.94, self.orchestratorTargetProgress + 0.10)
                let asymptoticCreep = min(creepCeiling, 0.90 * (1.0 - exp(-elapsed / 8.0)))
                let actualProgress = min(0.96, max(self.orchestratorTargetProgress, asymptoticCreep))
                let target = min(actualProgress, visualEnvelope)
                if self.scanProgress < target {
                    let step = max(0.012, (target - self.scanProgress) * 0.26)
                    self.scanProgress = min(1.0, max(0.0, min(target, self.scanProgress + step)))
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.progressTimer = timer

        let orchestrator = self.orchestrator
        Task.detached(priority: .userInitiated) { [weak self] in
            let fullResult = await orchestrator.runScan(
                scopes: Set(ScanScope.allCases),
                onProgressUpdate: { [weak self] fraction, rawStage in
                    DispatchQueue.main.async {
                        guard let self, self.isScanning else { return }
                        let clampedFraction = min(1.0, max(0.0, fraction))
                        self.orchestratorTargetProgress = max(self.orchestratorTargetProgress, clampedFraction)
                        self.rawProgressStageMessage = rawStage
                        self.statusMessage = L10n.localizedProgressStage(rawStage, language: self.language)
                    }
                }
            )
            let upgraded = fullResult.upgradedWithAICategory()
            let scoped = upgraded.filtered(by: activeScopes)

            let elapsed = Date().timeIntervalSince(scanStartTime)
            let remainingWait = max(0.0, minVisualDuration - elapsed)
            if remainingWait > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remainingWait * 1_000_000_000))
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.progressTimer?.invalidate()
                self.progressTimer = nil

                self.scanProgress = 1.0
                self.scanElapsedSeconds = scoped.scanDurationSeconds
                self.rawProgressStageMessage = "Scan complete."
                self.statusMessage = L10n.localizedProgressStage("Scan complete.", language: self.language)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                    guard let self else { return }
                    withAnimation(InnotecTheme.fluidSpring) {
                        self.unfilteredReport = upgraded
                        self.report = scoped
                        self.selectedCategoryID = scoped.categories.first?.id
                        self.selectedAppGroupID = scoped.categories.first?.appGroups.first?.id
                        self.isScanning = false
                        self.statusMessage = L10n.scanCompletedStatus(
                            language: self.language,
                            duration: scoped.scanDurationSeconds,
                            guardedCount: scoped.protectedPathsSkippedCount,
                            activeScopes: activeScopes.count,
                            totalScopes: ScanScope.allCases.count
                        )
                    }
                }
            }
        }
    }

    public var selectedCategoryGroup: CleanupCategoryGroup? {
        guard let report, let selectedCategoryID else { return nil }
        return report.categories.first { $0.id == selectedCategoryID }
    }

    public var filteredAppGroups: [ApplicationBundleGroup] {
        guard let category = selectedCategoryGroup else { return [] }
        let byConfidence = category.appGroups(matching: confidenceFilter)
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return byConfidence }
        return byConfidence.filter { group in
            group.appDisplayName.localizedCaseInsensitiveContains(trimmed)
                || group.bundleIdentifier.localizedCaseInsensitiveContains(trimmed)
                || group.items.contains(where: { $0.path.localizedCaseInsensitiveContains(trimmed) })
        }
    }

    public func setConfidenceFilter(_ filter: ConfidenceFilter) {
        withAnimation(InnotecTheme.fluidSpring) {
            confidenceFilter = filter
            guard let report else { return }
            if let currentCat = selectedCategoryGroup,
                currentCat.appGroupCount(matching: filter) == 0,
                let firstMatchingCat = report.categories.first(where: { $0.appGroupCount(matching: filter) > 0 })
            {
                selectedCategoryID = firstMatchingCat.id
                selectedAppGroupID = firstMatchingCat.appGroups(matching: filter).first?.id
            }
        }
    }

    public func unselectAllReviewItems() {
        guard var currentReport = report else { return }
        withAnimation(InnotecTheme.fluidSpring) {
            for catIdx in currentReport.categories.indices {
                for grpIdx in currentReport.categories[catIdx].appGroups.indices {
                    for itemIdx in currentReport.categories[catIdx].appGroups[grpIdx].items.indices {
                        if currentReport.categories[catIdx].appGroups[grpIdx].items[itemIdx].confidence
                            == .reviewRecommended
                        {
                            currentReport.categories[catIdx].appGroups[grpIdx].items[itemIdx].isSelected = false
                        }
                    }
                }
            }
            report = currentReport
            syncSelectionToUnfiltered(from: currentReport)
        }
    }

    public var selectedAppGroup: ApplicationBundleGroup? {
        guard let category = selectedCategoryGroup, let selectedAppGroupID else { return nil }
        return category.appGroups.first { $0.id == selectedAppGroupID } ?? category.appGroups.first
    }

    private func syncSelectionToUnfiltered(from updatedReport: ScanReport) {
        lastDryRunSummary = nil
        guard var full = unfilteredReport else { return }
        for updatedCat in updatedReport.categories {
            if let fullCatIdx = full.categories.firstIndex(where: { $0.id == updatedCat.id }) {
                full.categories[fullCatIdx] = updatedCat
            }
        }
        unfilteredReport = full
    }

    public func toggleItemSelection(categoryID: String, appGroupID: String, itemID: String) {
        guard var currentReport = report,
            let catIdx = currentReport.categories.firstIndex(where: { $0.id == categoryID }),
            let grpIdx = currentReport.categories[catIdx].appGroups.firstIndex(where: { $0.id == appGroupID }),
            let itemIdx = currentReport.categories[catIdx].appGroups[grpIdx].items.firstIndex(where: { $0.id == itemID }
            )
        else { return }

        withAnimation(InnotecTheme.fluidSpring) {
            currentReport.categories[catIdx].appGroups[grpIdx].items[itemIdx].isSelected.toggle()
            report = currentReport
            syncSelectionToUnfiltered(from: currentReport)
        }
    }

    public func toggleAppGroupSelection(categoryID: String, appGroupID: String) {
        guard var currentReport = report,
            let catIdx = currentReport.categories.firstIndex(where: { $0.id == categoryID }),
            let grpIdx = currentReport.categories[catIdx].appGroups.firstIndex(where: { $0.id == appGroupID })
        else { return }

        let targetState = !currentReport.categories[catIdx].appGroups[grpIdx].isAllSelected
        withAnimation(InnotecTheme.fluidSpring) {
            for idx in currentReport.categories[catIdx].appGroups[grpIdx].items.indices {
                currentReport.categories[catIdx].appGroups[grpIdx].items[idx].isSelected = targetState
            }
            report = currentReport
            syncSelectionToUnfiltered(from: currentReport)
        }
    }

    public func toggleCategorySelection(categoryID: String) {
        guard var currentReport = report,
            let catIdx = currentReport.categories.firstIndex(where: { $0.id == categoryID })
        else { return }

        let targetState = !currentReport.categories[catIdx].isAllSelected
        withAnimation(InnotecTheme.fluidSpring) {
            for grpIdx in currentReport.categories[catIdx].appGroups.indices {
                for itemIdx in currentReport.categories[catIdx].appGroups[grpIdx].items.indices {
                    currentReport.categories[catIdx].appGroups[grpIdx].items[itemIdx].isSelected = targetState
                }
            }
            report = currentReport
            syncSelectionToUnfiltered(from: currentReport)
        }
    }

    public func toggleScopeCategoriesSelection(scope: ScanScope) {
        guard var currentReport = report else { return }
        let targetState = !currentReport.isScopeAllSelected(scope)
        withAnimation(InnotecTheme.fluidSpring) {
            for catIdx in currentReport.categories.indices
            where currentReport.categories[catIdx].category.scope == scope {
                for grpIdx in currentReport.categories[catIdx].appGroups.indices {
                    for itemIdx in currentReport.categories[catIdx].appGroups[grpIdx].items.indices {
                        currentReport.categories[catIdx].appGroups[grpIdx].items[itemIdx].isSelected = targetState
                    }
                }
            }
            report = currentReport
            syncSelectionToUnfiltered(from: currentReport)
        }
    }

    public func runDryRunVerification() {
        guard let report else { return }
        let allItems = report.categories.flatMap(\.appGroups).flatMap(\.items)
        let cleaner = SafeTrashCleaner()
        let summary = cleaner.execute(items: allItems, mode: .dryRunPreview)
        withAnimation(InnotecTheme.fluidSpring) {
            lastDryRunSummary = L10n.dryRunVerifiedStatus(
                language: language,
                itemsCount: summary.processedItemsCount,
                formattedBytes: ByteFormatter.string(from: summary.bytesReclaimed)
            )
        }
    }

    public func performCleanup() {
        guard let currentReport = report, !isScanning, !isCleaning, !isQuittingRunningApps else { return }
        let allItems = currentReport.categories.flatMap(\.appGroups).flatMap(\.items)
        let selectedItems = allItems.filter(\.isSelected)
        guard !selectedItems.isEmpty else { return }

        // Check in real time if any selected items belong to currently open GUI applications
        let conflicts = RunningAppCleanupCoordinator.detectConflicts(for: selectedItems)
        if !conflicts.isEmpty {
            withAnimation(InnotecTheme.fluidSpring) {
                self.pendingRunningAppConflicts = conflicts
                self.isQuittingRunningApps = false
            }
            return
        }

        executeCleanup(items: selectedItems)
    }

    public func cancelRunningAppConflictsModal() {
        withAnimation(InnotecTheme.fluidSpring) {
            self.pendingRunningAppConflicts = []
            self.isQuittingRunningApps = false
        }
    }

    public func confirmCleanWithoutClosing() {
        guard let currentReport = report else { return }
        let selectedItems = currentReport.categories.flatMap(\.appGroups).flatMap(\.items).filter(\.isSelected)
        withAnimation(InnotecTheme.fluidSpring) {
            self.pendingRunningAppConflicts = []
            self.isQuittingRunningApps = false
        }
        executeCleanup(items: selectedItems)
    }

    public func confirmSkipOpenAppsAndClean() {
        guard let currentReport = report else { return }
        let conflictItemIDs = Set(pendingRunningAppConflicts.flatMap(\.affectedItemIDs))
        let remainingItems = currentReport.categories
            .flatMap(\.appGroups)
            .flatMap(\.items)
            .filter { $0.isSelected && !conflictItemIDs.contains($0.id) }

        withAnimation(InnotecTheme.fluidSpring) {
            self.pendingRunningAppConflicts = []
            self.isQuittingRunningApps = false
        }

        guard !remainingItems.isEmpty else { return }
        executeCleanup(items: remainingItems)
    }

    public func confirmQuitAppsAndClean() {
        guard let currentReport = report, !isQuittingRunningApps else { return }
        let conflictsToQuit = pendingRunningAppConflicts
        let selectedItems = currentReport.categories.flatMap(\.appGroups).flatMap(\.items).filter(\.isSelected)

        withAnimation(InnotecTheme.fluidSpring) {
            self.isQuittingRunningApps = true
        }

        Task {
            _ = await RunningAppCleanupCoordinator.terminateApplications(
                conflictsToQuit,
                forceIfNeeded: true,
                timeoutSeconds: 3.0
            )
            await MainActor.run {
                withAnimation(InnotecTheme.fluidSpring) {
                    self.pendingRunningAppConflicts = []
                    self.isQuittingRunningApps = false
                }
                self.executeCleanup(items: selectedItems)
            }
        }
    }

    private func executeCleanup(items selectedItems: [ScanCandidateItem]) {
        guard !isScanning, !isCleaning, !selectedItems.isEmpty else { return }
        let totalSelectedBytes = selectedItems.reduce(UInt64(0)) { $0 + $1.allocatedBytes }
        let firstLabel = "\(selectedItems[0].appDisplayName) — \(selectedItems[0].itemName)"

        // Reset progress counters outside spring animation so repeated cleanups start cleanly at 0%
        cleaningTimer?.invalidate()
        cleaningProgress = 0.0
        cleaningElapsedSeconds = 0.0
        cleaningTargetProgress = 0.04
        cleaningTargetCount = selectedItems.count
        cleaningTargetBytes = totalSelectedBytes
        cleaningCurrentItemText = firstLabel

        withAnimation(InnotecTheme.fluidSpring) {
            isCleaning = true
        }

        let cleanStartTime = Date()
        let minVisualDuration: Double = 1.05

        let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, self.isCleaning else {
                    t.invalidate()
                    return
                }
                let elapsed = Date().timeIntervalSince(cleanStartTime)
                self.cleaningElapsedSeconds = elapsed
                let visualEnvelope = min(0.96, (elapsed / minVisualDuration) * 0.96)
                let actualProgress = min(0.96, max(self.cleaningTargetProgress, visualEnvelope * 0.25))
                let target = min(actualProgress, visualEnvelope)
                if self.cleaningProgress < target {
                    let step = max(0.015, (target - self.cleaningProgress) * 0.28)
                    self.cleaningProgress = min(1.0, max(0.0, min(target, self.cleaningProgress + step)))
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.cleaningTimer = timer

        Task.detached(priority: .userInitiated) { [weak self] in
            let cleaner = SafeTrashCleaner()
            let summary = cleaner.execute(
                items: selectedItems,
                mode: .permanentDelete,
                onProgressUpdate: { [weak self] fraction, itemLabel in
                    DispatchQueue.main.async {
                        guard let self, self.isCleaning else { return }
                        let clampedFraction = min(1.0, max(0.0, fraction))
                        self.cleaningTargetProgress = max(self.cleaningTargetProgress, clampedFraction)
                        self.cleaningCurrentItemText = itemLabel
                    }
                }
            )

            let elapsed = Date().timeIntervalSince(cleanStartTime)
            let remainingWait = max(0.0, minVisualDuration - elapsed)
            if remainingWait > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remainingWait * 1_000_000_000))
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.cleaningTimer?.invalidate()
                self.cleaningTimer = nil

                self.cleaningProgress = 1.0
                self.cleaningElapsedSeconds = Date().timeIntervalSince(cleanStartTime)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { [weak self] in
                    guard let self else { return }
                    withAnimation(InnotecTheme.fluidSpring) {
                        if let full = self.unfilteredReport {
                            self.unfilteredReport = full.removingItems(withIDs: summary.cleanedItemIDs)
                        }
                        if let active = self.report {
                            let pruned = active.removingItems(withIDs: summary.cleanedItemIDs)
                            self.report = pruned
                            if let selCat = self.selectedCategoryID,
                                let matchingCat = pruned.categories.first(where: { $0.id == selCat })
                            {
                                if let selGrp = self.selectedAppGroupID,
                                    matchingCat.appGroups.contains(where: { $0.id == selGrp })
                                {
                                    // Keep current selection
                                } else {
                                    self.selectedAppGroupID = matchingCat.appGroups.first?.id
                                }
                            } else {
                                self.selectedCategoryID = pruned.categories.first?.id
                                self.selectedAppGroupID = pruned.categories.first?.appGroups.first?.id
                            }
                        }
                        self.isCleaning = false
                        self.lastDryRunSummary = L10n.cleanupCompletedStatus(
                            language: self.language,
                            movedCount: summary.processedItemsCount,
                            formattedBytes: ByteFormatter.string(from: summary.bytesReclaimed),
                            skippedCount: summary.skippedProtectedCount,
                            errorCount: summary.errors.count
                        )
                    }
                }
            }
        }
    }

    public func revealInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

private struct LanguageSwitcherFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

public struct MainDashboardView: View {
    @StateObject private var viewModel: ScanViewModel
    @State private var isLanguageMenuExpanded: Bool = false
    @State private var languageButtonFrame: CGRect = .zero
    @State private var scanPulseAnimated: Bool = false
    @State private var scanSweepRotation: Double = 0.0
    @Namespace private var glassNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let isStaticSnapshot: Bool

    public init(
        initialReport: ScanReport? = nil,
        showScopeSelectorInitially: Bool? = nil,
        isStaticSnapshot: Bool? = nil,
        initialLanguage: AppLanguage? = nil,
        simulateScanningState: Bool = false,
        simulateCleaningState: Bool = false
    ) {
        self.isStaticSnapshot =
            isStaticSnapshot ?? (initialReport != nil || simulateScanningState || simulateCleaningState)
        _viewModel = StateObject(
            wrappedValue: ScanViewModel(
                initialReport: initialReport,
                showScopeSelectorInitially: showScopeSelectorInitially,
                initialLanguage: initialLanguage,
                simulateScanningState: simulateScanningState,
                simulateCleaningState: simulateCleaningState
            )
        )
    }

    public var body: some View {
        GeometryReader { rootGeo in
            ZStack(alignment: .topLeading) {
                // Layer 0: Luminous White Canvas with Flowing Purple-Green Vector Lines
                InnotecAmbientCanvas()

                // Layer 1 & 2: Native Swift 6.4 / macOS 26+ White Liquid Glass Container
                GlassEffectContainer(spacing: 14) {
                    if viewModel.isShowingScopeSelector {
                        preScanScopeSelectionView
                            .padding(.top, isStaticSnapshot ? 24 : 40)
                            .padding(.horizontal, 44)
                            .padding(.bottom, 32)
                            .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    } else if viewModel.isScanning {
                        scanningProgressView
                            .padding(.top, isStaticSnapshot ? 24 : 40)
                            .padding(.horizontal, 44)
                            .padding(.bottom, 32)
                            .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    } else if viewModel.isCleaning {
                        cleaningProgressView
                            .padding(.top, isStaticSnapshot ? 24 : 40)
                            .padding(.horizontal, 44)
                            .padding(.bottom, 32)
                            .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    } else {
                        VStack(spacing: 16) {
                            resultsTopBar
                                .zIndex(50)

                            HStack(spacing: 18) {
                                categorySidebarIsland
                                    .frame(width: 384)

                                categoryInspectorIsland
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .zIndex(1)

                            footerCommandDock
                        }
                        .padding(.top, isStaticSnapshot ? 22 : 36)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 20)
                        .transition(.opacity.combined(with: .scale(scale: 0.99)))
                    }
                }

                // Layer 2.5: Pre-Clean Running Applications Interception Sheet
                if !viewModel.pendingRunningAppConflicts.isEmpty {
                    Color.black.opacity(0.26)
                        .ignoresSafeArea()
                        .onTapGesture {
                            if !viewModel.isQuittingRunningApps {
                                viewModel.cancelRunningAppConflictsModal()
                            }
                        }
                        .transition(.opacity)
                        .zIndex(950)

                    runningAppConflictsModalCard
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .zIndex(951)
                }

                // Layer 3: Top-Level Vertical Language Selector Dropdown (Above All GlassEffect Portals)
                if isLanguageMenuExpanded {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(InnotecTheme.fluidSpring) {
                                isLanguageMenuExpanded = false
                            }
                        }
                        .zIndex(998)

                    languageDropdownMenuCard
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(
                            .top,
                            languageButtonFrame.height > 0
                                ? languageButtonFrame.maxY + 6
                                : ((isStaticSnapshot ? 22 : 36) + 42)
                        )
                        .padding(
                            .trailing,
                            languageButtonFrame.width > 0
                                ? max(16, rootGeo.size.width - languageButtonFrame.maxX)
                                : (viewModel.isShowingScopeSelector || viewModel.isScanning ? 44 : 32)
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .topTrailing)))
                        .zIndex(999)
                }
            }
            .coordinateSpace(name: "MacSweepRootSpace")
            .onPreferenceChange(LanguageSwitcherFramePreferenceKey.self) { newFrame in
                if newFrame != .zero {
                    languageButtonFrame = newFrame
                }
            }
        }
        .preferredColorScheme(.light)
        .frame(minWidth: 1260, minHeight: 800)
    }

    // MARK: - Vertical Language Selector (Shows Active Language Only, Expands Vertically on Click)

    private var languageSwitcherPill: some View {
        Button {
            withAnimation(InnotecTheme.fluidSpring) {
                isLanguageMenuExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(InnotecTheme.royalPurple)

                Text(viewModel.language.shortLabel)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(InnotecTheme.inkPrimary)

                Image(systemName: isLanguageMenuExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(InnotecTheme.royalPurple)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8.5)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.96))
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                InnotecTheme.royalPurple.opacity(0.55),
                                InnotecTheme.mintTeal.opacity(0.65),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1.15
                    )
            )
            .shadow(color: InnotecTheme.royalPurple.opacity(0.10), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(AppleFluidPressStyle())
        .fixedSize(horizontal: true, vertical: false)
        .help(viewModel.language.displayName)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: LanguageSwitcherFramePreferenceKey.self,
                    value: geo.frame(in: .named("MacSweepRootSpace"))
                )
            }
        )
    }

    private var languageDropdownMenuCard: some View {
        let otherLanguages = AppLanguage.allCases.filter { $0 != viewModel.language }

        return VStack(alignment: .leading, spacing: 5) {
            ForEach(otherLanguages) { lang in
                Button {
                    withAnimation(InnotecTheme.fluidSpring) {
                        viewModel.setLanguage(lang)
                        isLanguageMenuExpanded = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(lang.shortLabel)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(InnotecTheme.royalPurple)
                            .frame(width: 22, alignment: .leading)

                        Text(lang.displayName)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(InnotecTheme.inkPrimary)

                        Spacer(minLength: 6)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .frame(width: 126, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(InnotecTheme.lavenderTint.opacity(0.82))
                    )
                }
                .buttonStyle(AppleFluidPressStyle())
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.99))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            InnotecTheme.royalPurple.opacity(0.60),
                            InnotecTheme.mintTeal.opacity(0.70),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        )
        .shadow(color: InnotecTheme.royalPurple.opacity(0.20), radius: 16, x: 0, y: 8)
    }

    // MARK: - Dedicated Scanning Progress Screen (Animated Radar + Progress Bar)

    private var scanningProgressView: some View {
        let clampedProgress = min(max(viewModel.scanProgress, 0.0), 1.0)
        let percentageInt = min(100, max(0, Int((clampedProgress * 100.0).rounded())))
        let activeSortedScopes = ScanScope.allCases.filter { viewModel.selectedScopes.contains($0) }

        return VStack(spacing: 24) {
            // 1. Top Bar: Brand Lockup + Vertical Language Selector
            HStack(alignment: .center) {
                InnotecBrandLockup(language: viewModel.language)
                Spacer()
                languageSwitcherPill
            }
            .zIndex(50)

            Spacer(minLength: 12)

            // 2. Centered Liquid Glass Scanning Card
            VStack(spacing: 26) {
                // Animated Radar / Pulse Emblem
                ZStack {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    InnotecTheme.royalPurple.opacity(0.24),
                                    InnotecTheme.mintTeal.opacity(0.28),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                        .frame(width: 132, height: 132)
                        .scaleEffect(scanPulseAnimated ? 1.12 : 0.92)
                        .opacity(scanPulseAnimated ? 0.25 : 0.75)

                    Circle()
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    InnotecTheme.royalPurple.opacity(0.05),
                                    InnotecTheme.royalPurple.opacity(0.55),
                                    InnotecTheme.mintTeal.opacity(0.85),
                                    InnotecTheme.royalPurple.opacity(0.05),
                                ]),
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 3.0, lineCap: .round)
                        )
                        .frame(width: 104, height: 104)
                        .rotationEffect(.degrees(scanSweepRotation))

                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    InnotecTheme.royalPurple,
                                    InnotecTheme.electricViolet,
                                    InnotecTheme.mintTeal,
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 74, height: 74)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.75), lineWidth: 1.3)
                        )
                        .shadow(color: InnotecTheme.royalPurple.opacity(0.26), radius: 14, x: 0, y: 6)

                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.top, 4)

                // Title & Subtitle
                VStack(spacing: 8) {
                    Text(L10n.scanningInProgressTitle(viewModel.language))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .tracking(-0.5)
                        .foregroundStyle(InnotecTheme.inkPrimary)
                        .multilineTextAlignment(.center)

                    Text(L10n.scanningInProgressSubtitle(viewModel.language))
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(InnotecTheme.inkSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }

                // Active Scope Pills
                HStack(spacing: 10) {
                    ForEach(activeSortedScopes) { scope in
                        HStack(spacing: 6) {
                            Image(systemName: scope.systemSymbolName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(InnotecTheme.royalPurple)
                            Text(scope.title(in: viewModel.language))
                                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(InnotecTheme.inkPrimary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(InnotecTheme.lavenderTint.opacity(0.85))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            InnotecTheme.royalPurple.opacity(0.40),
                                            InnotecTheme.mintTeal.opacity(0.50),
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 1.0
                                )
                        )
                    }
                }

                // Smooth Progress Bar + Stage Label + Percentage + Elapsed Time
                VStack(spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(InnotecTheme.luminousMint)
                                .frame(width: 8, height: 8)
                            Text(viewModel.statusMessage)
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(InnotecTheme.inkPrimary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 12)

                        HStack(spacing: 10) {
                            Text(
                                L10n.scanningElapsedBadge(
                                    seconds: viewModel.scanElapsedSeconds, language: viewModel.language)
                            )
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(InnotecTheme.inkSecondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(InnotecTheme.pearlSurface)
                            )

                            Text("\(percentageInt)%")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(InnotecTheme.royalPurple)
                        }
                    }

                    // Progress Bar Track & Animated Fill
                    GeometryReader { barGeo in
                        let trackWidth = max(0, barGeo.size.width)
                        let fillWidth = min(
                            trackWidth, max(trackWidth > 0 ? 14 : 0, trackWidth * CGFloat(clampedProgress)))
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(InnotecTheme.lavenderTint)
                                .overlay(
                                    Capsule()
                                        .strokeBorder(
                                            InnotecTheme.royalPurple.opacity(0.22),
                                            lineWidth: 1.0
                                        )
                                )

                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            InnotecTheme.royalPurple,
                                            InnotecTheme.electricViolet,
                                            InnotecTheme.mintTeal,
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: fillWidth)
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.white.opacity(0.55), lineWidth: 0.8)
                                )
                                .shadow(color: InnotecTheme.mintTeal.opacity(0.32), radius: 8, x: 0, y: 2)
                        }
                        .clipShape(Capsule())
                    }
                    .frame(height: 14)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.88))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    InnotecTheme.royalPurple.opacity(0.28),
                                    InnotecTheme.mintTeal.opacity(0.38),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1.0
                        )
                )
            }
            .padding(.horizontal, 38)
            .padding(.vertical, 36)
            .frame(maxWidth: 660)
            .innotecLiquidGlass(
                cornerRadius: 26,
                tint: InnotecTheme.electricViolet,
                tintOpacity: 0.16,
                isInteractive: false,
                isStaticSnapshot: isStaticSnapshot,
                isElevated: true
            )

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !isStaticSnapshot && !reduceMotion else { return }
            scanPulseAnimated = false
            scanSweepRotation = 0.0
            withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true)) {
                scanPulseAnimated = true
            }
            withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                scanSweepRotation = 360.0
            }
        }
    }

    // MARK: - Dedicated Cleaning Progress Screen (Animated Trash Radar + Progress Bar)

    private var cleaningProgressView: some View {
        let clampedProgress = min(max(viewModel.cleaningProgress, 0.0), 1.0)
        let percentageInt = min(100, max(0, Int((clampedProgress * 100.0).rounded())))

        return VStack(spacing: 24) {
            // 1. Top Bar: Brand Lockup + Vertical Language Selector
            HStack(alignment: .center) {
                InnotecBrandLockup(language: viewModel.language)
                Spacer()
                languageSwitcherPill
            }
            .zIndex(50)

            Spacer(minLength: 12)

            // 2. Centered Liquid Glass Cleaning Card
            VStack(spacing: 26) {
                // Animated Radar / Pulse Emblem (Emerald / Mint / Purple)
                ZStack {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    InnotecTheme.luminousMint.opacity(0.28),
                                    InnotecTheme.royalPurple.opacity(0.24),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                        .frame(width: 132, height: 132)
                        .scaleEffect(scanPulseAnimated ? 1.12 : 0.92)
                        .opacity(scanPulseAnimated ? 0.25 : 0.78)

                    Circle()
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    InnotecTheme.luminousMint.opacity(0.05),
                                    InnotecTheme.luminousMint.opacity(0.65),
                                    InnotecTheme.royalPurple.opacity(0.85),
                                    InnotecTheme.luminousMint.opacity(0.05),
                                ]),
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 3.0, lineCap: .round)
                        )
                        .frame(width: 104, height: 104)
                        .rotationEffect(.degrees(scanSweepRotation))

                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    InnotecTheme.luminousMint,
                                    InnotecTheme.mintTeal,
                                    InnotecTheme.royalPurple,
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 74, height: 74)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.75), lineWidth: 1.3)
                        )
                        .shadow(color: InnotecTheme.luminousMint.opacity(0.28), radius: 14, x: 0, y: 6)

                    Image(systemName: "sparkles")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.top, 4)

                // Title & Subtitle
                VStack(spacing: 8) {
                    Text(L10n.cleaningInProgressTitle(viewModel.language))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .tracking(-0.5)
                        .foregroundStyle(InnotecTheme.inkPrimary)
                        .multilineTextAlignment(.center)

                    Text(L10n.cleaningInProgressSubtitle(viewModel.language))
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(InnotecTheme.inkSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }

                // Target Summary Pill
                HStack(spacing: 6) {
                    Image(systemName: "internaldrive.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(InnotecTheme.electricViolet)
                    Text(
                        "\(L10n.itemsCountBadge(viewModel.cleaningTargetCount, viewModel.language)) • \(ByteFormatter.string(from: viewModel.cleaningTargetBytes))"
                    )
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(InnotecTheme.inkPrimary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.92)))
                .overlay(
                    Capsule()
                        .strokeBorder(InnotecTheme.electricViolet.opacity(0.35), lineWidth: 1.0)
                )

                // Smooth Progress Bar + Current Item Label + Percentage + Elapsed Time
                VStack(spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(InnotecTheme.luminousMint)
                                .frame(width: 8, height: 8)
                            Text(viewModel.cleaningCurrentItemText)
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(InnotecTheme.inkPrimary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 12)

                        HStack(spacing: 10) {
                            Text(
                                L10n.scanningElapsedBadge(
                                    seconds: viewModel.cleaningElapsedSeconds, language: viewModel.language)
                            )
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(InnotecTheme.inkSecondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(InnotecTheme.pearlSurface)
                            )

                            Text("\(percentageInt)%")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(InnotecTheme.luminousMint)
                        }
                    }

                    // Progress Bar Track & Animated Fill
                    GeometryReader { barGeo in
                        let trackWidth = max(0, barGeo.size.width)
                        let fillWidth = min(
                            trackWidth, max(trackWidth > 0 ? 14 : 0, trackWidth * CGFloat(clampedProgress)))
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(InnotecTheme.mintSurfaceTint)
                                .overlay(
                                    Capsule()
                                        .strokeBorder(
                                            InnotecTheme.luminousMint.opacity(0.28),
                                            lineWidth: 1.0
                                        )
                                )

                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            InnotecTheme.luminousMint,
                                            InnotecTheme.mintTeal,
                                            InnotecTheme.royalPurple,
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: fillWidth)
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.white.opacity(0.55), lineWidth: 0.8)
                                )
                                .shadow(color: InnotecTheme.luminousMint.opacity(0.32), radius: 8, x: 0, y: 2)
                        }
                        .clipShape(Capsule())
                    }
                    .frame(height: 14)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.88))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    InnotecTheme.luminousMint.opacity(0.38),
                                    InnotecTheme.royalPurple.opacity(0.28),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1.0
                        )
                )
            }
            .padding(.horizontal, 38)
            .padding(.vertical, 36)
            .frame(maxWidth: 660)
            .innotecLiquidGlass(
                cornerRadius: 26,
                tint: InnotecTheme.mintTeal,
                tintOpacity: 0.16,
                isInteractive: false,
                isStaticSnapshot: isStaticSnapshot,
                isElevated: true
            )

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !isStaticSnapshot && !reduceMotion else { return }
            scanPulseAnimated = false
            scanSweepRotation = 0.0
            withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true)) {
                scanPulseAnimated = true
            }
            withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                scanSweepRotation = 360.0
            }
        }
    }

    // MARK: - Minimalist Centered Opening Screen (No Scan on Launch, No Top Line)

    private var preScanScopeSelectionView: some View {
        VStack(spacing: 28) {
            // 1. Simple Top Bar: Brand Lockup + TCC Permission Helper + Language Switcher (no top line)
            HStack(alignment: .center, spacing: 10) {
                InnotecBrandLockup(language: viewModel.language)
                Spacer()
                fullDiskAccessStatusPill
                languageSwitcherPill
            }
            .zIndex(50)

            Spacer(minLength: 8)

            // 2. Centered Title & Short Subtitle
            VStack(spacing: 8) {
                Text(L10n.welcomeTitle(viewModel.language))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .tracking(-0.6)
                    .foregroundStyle(InnotecTheme.inkPrimary)
                    .multilineTextAlignment(.center)

                Text(L10n.welcomeSubtitle(viewModel.language))
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(InnotecTheme.inkSecondary)
                    .multilineTextAlignment(.center)
            }

            // 3. Three Minimalist Centered Scope Cards (General, Developer, AI)
            HStack(spacing: 24) {
                ForEach(ScanScope.allCases) { scope in
                    scopeSelectorCard(for: scope)
                }
            }
            .frame(maxWidth: 1120, maxHeight: 340)

            Spacer(minLength: 8)

            // 4. Centered Start Scan Action Button
            VStack(spacing: 10) {
                Button {
                    viewModel.startScopedScan(forceFresh: true)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15, weight: .bold))
                        Text(L10n.startScanButton(viewModel.language))
                            .font(.system(size: 15.5, weight: .bold, design: .rounded))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13.5, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 34)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        InnotecTheme.royalPurple, InnotecTheme.electricViolet, InnotecTheme.mintTeal,
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.65), lineWidth: 1.2)
                    )
                    .shadow(color: InnotecTheme.royalPurple.opacity(0.26), radius: 12, x: 0, y: 5)
                }
                .buttonStyle(AppleFluidPressStyle())
                .disabled(viewModel.selectedScopes.isEmpty)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard !isStaticSnapshot else { return }
            viewModel.refreshFullDiskAccessStatus()
        }
    }

    private var fullDiskAccessStatusPill: some View {
        let isGranted = viewModel.hasFullDiskAccess
        return Button {
            viewModel.openFullDiskAccessSettings()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isGranted ? "checkmark.shield.fill" : "lock.shield")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(isGranted ? InnotecTheme.luminousMint : InnotecTheme.royalPurple)

                Text(
                    isGranted
                        ? L10n.fullDiskAccessGrantedBadge(viewModel.language)
                        : L10n.fullDiskAccessOptionalPrompt(viewModel.language)
                )
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(InnotecTheme.inkPrimary)

                if !isGranted {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(InnotecTheme.royalPurple)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.95))
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                (isGranted ? InnotecTheme.luminousMint : InnotecTheme.royalPurple).opacity(0.48),
                                InnotecTheme.mintTeal.opacity(0.58),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1.1
                    )
            )
            .shadow(color: InnotecTheme.royalPurple.opacity(0.08), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(AppleFluidPressStyle())
        .fixedSize(horizontal: true, vertical: false)
        .help(L10n.fullDiskAccessTooltip(viewModel.language))
    }

    private func scopeSelectorCard(for scope: ScanScope) -> some View {
        let isSelected = viewModel.selectedScopes.contains(scope)

        return Button {
            viewModel.toggleScope(scope)
        } label: {
            VStack(alignment: .center, spacing: 18) {
                Spacer(minLength: 4)

                // Centered Icon Badge
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            isSelected
                                ? LinearGradient(
                                    colors: [
                                        InnotecTheme.royalPurple, InnotecTheme.electricViolet, InnotecTheme.mintTeal,
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [InnotecTheme.lavenderTint, InnotecTheme.mintSurfaceTint],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            InnotecTheme.royalPurple.opacity(isSelected ? 0.70 : 0.40),
                                            InnotecTheme.mintTeal.opacity(isSelected ? 0.80 : 0.45),
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.2
                                )
                        )
                        .shadow(
                            color: isSelected ? InnotecTheme.royalPurple.opacity(0.22) : .clear,
                            radius: 12,
                            x: 0,
                            y: 6
                        )

                    Image(systemName: scope.systemSymbolName)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : InnotecTheme.royalPurple)
                }
                .frame(width: 72, height: 72)

                // Centered Title + Short Explanation
                VStack(alignment: .center, spacing: 8) {
                    Text(scope.title(in: viewModel.language))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .tracking(-0.3)
                        .foregroundStyle(InnotecTheme.inkPrimary)
                        .multilineTextAlignment(.center)

                    Text(scope.shortDescription(in: viewModel.language))
                        .font(.system(size: 13, weight: .regular))
                        .lineSpacing(3)
                        .foregroundStyle(InnotecTheme.inkSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 250)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                // Centered Selection Pill
                HStack(spacing: 6) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13, weight: .bold))
                    Text(isSelected ? L10n.selectedBadge(viewModel.language) : L10n.unselectedBadge(viewModel.language))
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(isSelected ? .white : InnotecTheme.inkSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(
                            isSelected
                                ? LinearGradient(
                                    colors: [InnotecTheme.royalPurple, InnotecTheme.mintTeal],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                : LinearGradient(
                                    colors: [InnotecTheme.pearlSurface, Color.white],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                        )
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    InnotecTheme.royalPurple.opacity(isSelected ? 0.65 : 0.35),
                                    InnotecTheme.mintTeal.opacity(isSelected ? 0.75 : 0.45),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1.0
                        )
                )
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .innotecLiquidGlass(
                cornerRadius: 22,
                tint: isSelected ? InnotecTheme.electricViolet : InnotecTheme.royalPurple,
                tintOpacity: isSelected ? 0.28 : 0.08,
                isInteractive: true,
                isStaticSnapshot: isStaticSnapshot,
                isElevated: isSelected
            )
            .opacity(isSelected ? 1.0 : 0.76)
        }
        .buttonStyle(AppleFluidPressStyle(scaleAmount: 0.985))
    }

    // MARK: - Top Bar (Clean, Unboxed, Minimalist Summary Pill)

    private var resultsTopBar: some View {
        HStack(spacing: 16) {
            InnotecBrandLockup(language: viewModel.language)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 12)

            if let report = viewModel.report {
                summaryMetricsPill(report: report)
                    .fixedSize(horizontal: true, vertical: false)
            }

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                scopePickerReturnButton
                rescanActionButton
                languageSwitcherPill
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private func summaryMetricsPill(report: ScanReport) -> some View {
        HStack(spacing: 10) {
            metricSummaryItem(
                label: L10n.summaryTotalLabel(viewModel.language),
                value: ByteFormatter.string(from: report.grandTotalBytes),
                dotColor: InnotecTheme.royalPurple,
                valueColor: InnotecTheme.inkPrimary,
                filter: .all
            )

            Rectangle()
                .fill(InnotecTheme.royalPurple.opacity(0.14))
                .frame(width: 1, height: 22)

            metricSummaryItem(
                label: L10n.summarySafeLabel(viewModel.language),
                value: ByteFormatter.string(from: report.safeAutoSelectedBytes),
                dotColor: InnotecTheme.luminousMint,
                valueColor: InnotecTheme.luminousMint,
                filter: .safeOnly
            )

            Rectangle()
                .fill(InnotecTheme.royalPurple.opacity(0.14))
                .frame(width: 1, height: 22)

            metricSummaryItem(
                label: L10n.summaryReviewLabel(viewModel.language),
                value: ByteFormatter.string(from: report.reviewRecommendedBytes),
                dotColor: InnotecTheme.amberReview,
                valueColor: InnotecTheme.amberReview,
                filter: .needsReview
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.92))
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            InnotecTheme.royalPurple.opacity(0.32),
                            InnotecTheme.mintTeal.opacity(0.42),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1.1
                )
        )
        .shadow(color: InnotecTheme.royalPurple.opacity(0.08), radius: 8, x: 0, y: 3)
    }

    private func metricSummaryItem(
        label: String,
        value: String,
        dotColor: Color,
        valueColor: Color,
        filter: ConfidenceFilter
    ) -> some View {
        let isActive = (viewModel.confidenceFilter == filter)
        return Button {
            if viewModel.confidenceFilter == filter && filter != .all {
                viewModel.setConfidenceFilter(.all)
            } else {
                viewModel.setConfidenceFilter(filter)
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(isActive ? InnotecTheme.inkPrimary : InnotecTheme.inkSecondary)

                    Text(value)
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(valueColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(
                        isActive && filter != .all
                            ? dotColor.opacity(0.14)
                            : (isActive && viewModel.confidenceFilter == .all
                                ? InnotecTheme.lavenderTint.opacity(0.55) : Color.clear))
            )
        }
        .buttonStyle(AppleFluidPressStyle(scaleAmount: 0.96))
    }

    private var scopePickerReturnButton: some View {
        Button {
            withAnimation(InnotecTheme.fluidSpring) {
                isLanguageMenuExpanded = false
                viewModel.isShowingScopeSelector = true
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11.5, weight: .bold))
                Text(
                    "\(L10n.scopesButton(viewModel.language)) (\(viewModel.selectedScopes.count)/\(ScanScope.allCases.count))"
                )
                .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundStyle(InnotecTheme.royalPurple)
            .padding(.horizontal, 13)
            .padding(.vertical, 8.5)
            .background(
                Capsule()
                    .fill(InnotecTheme.lavenderTint)
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [InnotecTheme.royalPurple.opacity(0.50), InnotecTheme.mintTeal.opacity(0.60)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1.1
                    )
            )
        }
        .buttonStyle(AppleFluidPressStyle())
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var rescanActionButton: some View {
        Button {
            isLanguageMenuExpanded = false
            viewModel.performScan(forceFresh: true)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.system(size: 11.5, weight: .bold))
                Text(
                    viewModel.isScanning
                        ? L10n.scanningButton(viewModel.language) : L10n.rescanButton(viewModel.language)
                )
                .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundStyle(InnotecTheme.inkPrimary)
            .padding(.horizontal, 13)
            .padding(.vertical, 8.5)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.92))
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [InnotecTheme.royalPurple.opacity(0.55), InnotecTheme.mintTeal.opacity(0.65)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1.2
                    )
            )
            .shadow(color: InnotecTheme.royalPurple.opacity(0.08), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(AppleFluidPressStyle())
        .fixedSize(horizontal: true, vertical: false)
        .disabled(viewModel.isScanning)
    }

    // MARK: - Reusable Tri-State Checkbox (Scope, Domain, App Group)

    private func triStateCheckbox(
        isAllSelected: Bool,
        isPartiallySelected: Bool,
        size: CGFloat = 20,
        cornerRadius: CGFloat = 6,
        action: @escaping () -> Void
    ) -> some View {
        let isActive = isAllSelected || isPartiallySelected
        return Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        isActive
                            ? LinearGradient(
                                colors: [InnotecTheme.royalPurple, InnotecTheme.mintTeal],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [Color.white, InnotecTheme.pearlSurface],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                isActive
                                    ? Color.clear
                                    : InnotecTheme.royalPurple.opacity(0.35),
                                lineWidth: 1.2
                            )
                    )

                if isAllSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.50, weight: .heavy))
                        .foregroundStyle(.white)
                } else if isPartiallySelected {
                    Image(systemName: "minus")
                        .font(.system(size: size * 0.50, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
        }
        .buttonStyle(AppleFluidPressStyle(scaleAmount: 0.90))
    }

    // MARK: - Left Column: Scope-Divided Categories Sidebar with Whole-Domain Checkboxes

    private var categorySidebarIsland: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let report = viewModel.report {
                HStack(alignment: .center) {
                    Text(L10n.cleanupDomainsHeader(viewModel.language))
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(InnotecTheme.inkSecondary)

                    Spacer()

                    Text("\(report.categories.count)")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(InnotecTheme.lavenderTint))
                        .foregroundStyle(InnotecTheme.royalPurple)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 2)

                let maxCategoryBytes = max(1, report.categories.map(\.totalAllocatedBytes).max() ?? 1)

                optionalScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(ScanScope.allCases) { scope in
                            let scopeCategories = report.categories(for: scope)
                            if !scopeCategories.isEmpty {
                                scopeSidebarSection(
                                    scope: scope,
                                    categories: scopeCategories,
                                    report: report,
                                    maxCategoryBytes: maxCategoryBytes
                                )
                            }
                        }
                        Spacer(minLength: 4)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            } else {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.scanningFilesystemLabel(viewModel.language))
                        .font(.caption)
                        .foregroundStyle(InnotecTheme.inkSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .innotecLiquidGlass(
            cornerRadius: 20,
            tint: InnotecTheme.royalPurple,
            tintOpacity: 0.10,
            isInteractive: false,
            isStaticSnapshot: isStaticSnapshot,
            isElevated: true
        )
    }

    private func scopeSidebarSection(
        scope: ScanScope,
        categories: [CleanupCategoryGroup],
        report: ScanReport,
        maxCategoryBytes: UInt64
    ) -> some View {
        let scopeAllSelected = report.isScopeAllSelected(scope)
        let scopePartiallySelected = report.isScopePartiallySelected(scope)
        let scopeSelectedBytes = report.selectedAllocatedBytes(for: scope)
        let scopeTotalBytes = report.totalAllocatedBytes(for: scope)

        return VStack(alignment: .leading, spacing: 5) {
            // Scope Header Row (Checkbox + Scope Icon & Name + Scope Size)
            HStack(spacing: 8) {
                triStateCheckbox(
                    isAllSelected: scopeAllSelected,
                    isPartiallySelected: scopePartiallySelected,
                    size: 16,
                    cornerRadius: 5
                ) {
                    viewModel.toggleScopeCategoriesSelection(scope: scope)
                }

                Image(systemName: scope.systemSymbolName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(InnotecTheme.royalPurple)

                Text(scope.title(in: viewModel.language))
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(InnotecTheme.royalPurple)

                Spacer()

                Text(ByteFormatter.string(from: scopeSelectedBytes > 0 ? scopeSelectedBytes : scopeTotalBytes))
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(scopeSelectedBytes > 0 ? InnotecTheme.inkSecondary : InnotecTheme.inkMuted)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(InnotecTheme.lavenderTint.opacity(0.60))
            )

            // Scope's Cleanup Domains
            VStack(alignment: .leading, spacing: 5) {
                ForEach(categories) { catGroup in
                    categorySidebarRow(
                        catGroup: catGroup,
                        maxCategoryBytes: maxCategoryBytes
                    )
                }
            }
        }
    }

    private func categorySidebarRow(
        catGroup: CleanupCategoryGroup,
        maxCategoryBytes: UInt64
    ) -> some View {
        let isInspected = (viewModel.selectedCategoryID == catGroup.id)
        let isDomainChecked = catGroup.isAllSelected || catGroup.isPartiallySelected
        let totalFraction = Double(catGroup.totalAllocatedBytes) / Double(maxCategoryBytes)
        let matchingCount = catGroup.appGroupCount(matching: viewModel.confidenceFilter)
        let reviewCount = catGroup.reviewAppGroupCount

        return HStack(spacing: 9) {
            // Whole-Domain Select / Unselect Checkbox
            triStateCheckbox(
                isAllSelected: catGroup.isAllSelected,
                isPartiallySelected: catGroup.isPartiallySelected,
                size: 19,
                cornerRadius: 6
            ) {
                viewModel.toggleCategorySelection(categoryID: catGroup.id)
            }

            // Clicking the domain row inspects its items in the right column
            Button {
                withAnimation(reduceMotion ? .easeOut(duration: 0.15) : InnotecTheme.fluidSpring) {
                    viewModel.selectedCategoryID = catGroup.id
                    viewModel.selectedAppGroupID =
                        catGroup.appGroups(matching: viewModel.confidenceFilter).first?.id
                        ?? catGroup.appGroups.first?.id
                }
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 9) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    isInspected
                                        ? LinearGradient(
                                            colors: [InnotecTheme.royalPurple, InnotecTheme.mintTeal],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                        : LinearGradient(
                                            colors: [
                                                InnotecTheme.lavenderTint,
                                                InnotecTheme.mintSurfaceTint.opacity(0.75),
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                )

                            Image(systemName: catGroup.category.systemSymbolName)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(isInspected ? .white : InnotecTheme.royalPurple)
                        }
                        .frame(width: 28, height: 28)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(catGroup.category.title(in: viewModel.language))
                                .font(.system(size: 12.5, weight: isInspected ? .bold : .semibold, design: .rounded))
                                .foregroundStyle(isDomainChecked ? InnotecTheme.inkPrimary : InnotecTheme.inkSecondary)
                                .lineLimit(1)

                            HStack(spacing: 5) {
                                Text(
                                    L10n.itemsCountBadge(
                                        viewModel.confidenceFilter == .all ? catGroup.appGroups.count : matchingCount,
                                        viewModel.language
                                    )
                                )
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(InnotecTheme.inkSecondary)
                                .lineLimit(1)

                                if reviewCount > 0 {
                                    HStack(spacing: 2.5) {
                                        Circle()
                                            .fill(InnotecTheme.amberReview)
                                            .frame(width: 4.5, height: 4.5)
                                        Text("\(reviewCount)")
                                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                            .monospacedDigit()
                                            .foregroundStyle(InnotecTheme.amberReview)
                                    }
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(
                                        Capsule()
                                            .fill(InnotecTheme.amberReview.opacity(0.14))
                                    )
                                }
                            }
                        }

                        Spacer(minLength: 4)

                        VStack(alignment: .trailing, spacing: 1) {
                            Text(ByteFormatter.string(from: catGroup.totalAllocatedBytes))
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(
                                    isInspected
                                        ? InnotecTheme.royalPurple
                                        : (isDomainChecked ? InnotecTheme.inkSecondary : InnotecTheme.inkMuted)
                                )
                        }
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(InnotecTheme.royalPurple.opacity(0.08))
                            if totalFraction > 0 && isDomainChecked {
                                Capsule()
                                    .fill(
                                        isInspected
                                            ? LinearGradient(
                                                colors: [InnotecTheme.royalPurple, InnotecTheme.mintTeal],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                            : LinearGradient(
                                                colors: [
                                                    InnotecTheme.royalPurple.opacity(0.45),
                                                    InnotecTheme.mintTeal.opacity(0.55),
                                                ],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                    )
                                    .frame(width: max(6, geo.size.width * min(1.0, max(0.04, totalFraction))))
                            }
                        }
                    }
                    .frame(height: 2.5)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(AppleFluidPressStyle())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isInspected ? Color.white : Color.white.opacity(isDomainChecked ? 0.50 : 0.28))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isInspected
                        ? LinearGradient(
                            colors: [
                                InnotecTheme.royalPurple.opacity(0.55),
                                InnotecTheme.mintTeal.opacity(0.65),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        : LinearGradient(
                            colors: [
                                InnotecTheme.royalPurple.opacity(0.08),
                                InnotecTheme.royalPurple.opacity(0.05),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                    lineWidth: isInspected ? 1.4 : 0.8
                )
        )
        .shadow(
            color: isInspected ? InnotecTheme.royalPurple.opacity(0.11) : .clear,
            radius: 8,
            x: 0,
            y: 3
        )
        .opacity(viewModel.confidenceFilter != .all && matchingCount == 0 && !isInspected ? 0.48 : 1.0)
    }

    // MARK: - Right Column: Unified Category Inspector (Single Clean List, No Duplicate Columns)

    private var categoryInspectorIsland: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let catGroup = viewModel.selectedCategoryGroup {
                // Clean Category Header + Whole-Domain Checkbox + Search Bar
                VStack(alignment: .leading, spacing: 11) {
                    HStack(alignment: .center, spacing: 14) {
                        triStateCheckbox(
                            isAllSelected: catGroup.isAllSelected,
                            isPartiallySelected: catGroup.isPartiallySelected,
                            size: 22,
                            cornerRadius: 7
                        ) {
                            viewModel.toggleCategorySelection(categoryID: catGroup.id)
                        }

                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            InnotecTheme.lavenderTint,
                                            InnotecTheme.mintSurfaceTint,
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [
                                                    InnotecTheme.royalPurple.opacity(0.45),
                                                    InnotecTheme.mintTeal.opacity(0.55),
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1.0
                                        )
                                )

                            Image(systemName: catGroup.category.systemSymbolName)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(InnotecTheme.royalPurple)
                        }
                        .frame(width: 42, height: 42)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(catGroup.category.title(in: viewModel.language))
                                    .font(.system(size: 19, weight: .bold, design: .rounded))
                                    .tracking(-0.3)
                                    .foregroundStyle(InnotecTheme.inkPrimary)

                                if catGroup.selectedAllocatedBytes < catGroup.totalAllocatedBytes {
                                    Text(
                                        L10n.selectedOfTotalSummary(
                                            ByteFormatter.string(from: catGroup.selectedAllocatedBytes),
                                            ByteFormatter.string(from: catGroup.totalAllocatedBytes),
                                            viewModel.language
                                        )
                                    )
                                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(InnotecTheme.mintSurfaceTint))
                                    .foregroundStyle(InnotecTheme.luminousMint)
                                }
                            }

                            Text(catGroup.category.subtitle(in: viewModel.language))
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(InnotecTheme.inkSecondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 12)

                        // Compact Search Input
                        HStack(spacing: 7) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(InnotecTheme.royalPurple)

                            if isStaticSnapshot {
                                Text(L10n.cleanFilterPlaceholder(viewModel.language))
                                    .font(.system(size: 12))
                                    .foregroundStyle(InnotecTheme.inkMuted)
                                Spacer(minLength: 0)
                            } else {
                                TextField(L10n.cleanFilterPlaceholder(viewModel.language), text: $viewModel.searchQuery)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12))
                                    .foregroundStyle(InnotecTheme.inkPrimary)
                                if !viewModel.searchQuery.isEmpty {
                                    Button {
                                        viewModel.searchQuery = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(InnotecTheme.inkMuted)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .frame(width: 215)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.92))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    InnotecTheme.royalPurple.opacity(0.22),
                                    lineWidth: 1.0
                                )
                        )
                    }

                    // Confidence Filter Bar (shown only when the category has review items or a filter is active)
                    if catGroup.reviewAppGroupCount > 0
                        || viewModel.confidenceFilter != .all
                        || (viewModel.report?.selectedReviewItemCount ?? 0) > 0
                    {
                        confidenceFilterBar(for: catGroup)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)

                Rectangle()
                    .fill(InnotecTheme.royalPurple.opacity(0.08))
                    .frame(height: 1)
                    .padding(.horizontal, 20)

                let groupsToShow =
                    isStaticSnapshot
                    ? Array(viewModel.filteredAppGroups.prefix(6))
                    : viewModel.filteredAppGroups

                if groupsToShow.isEmpty {
                    VStack(spacing: 10) {
                        Image(
                            systemName: viewModel.confidenceFilter == .needsReview
                                ? "checkmark.shield.fill" : "line.3.horizontal.decrease.circle"
                        )
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(
                            viewModel.confidenceFilter == .needsReview
                                ? InnotecTheme.luminousMint
                                : InnotecTheme.royalPurple.opacity(0.55)
                        )

                        Text(L10n.noMatchingFilterItemsLabel(viewModel.confidenceFilter, viewModel.language))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(InnotecTheme.inkSecondary)

                        if viewModel.confidenceFilter != .all || !viewModel.searchQuery.isEmpty {
                            Button {
                                withAnimation(reduceMotion ? .easeOut(duration: 0.15) : InnotecTheme.fluidSpring) {
                                    viewModel.setConfidenceFilter(.all)
                                    viewModel.searchQuery = ""
                                }
                            } label: {
                                Text(L10n.showAllItemsButton(viewModel.language))
                                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                    .foregroundStyle(InnotecTheme.royalPurple)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule()
                                            .fill(InnotecTheme.lavenderTint)
                                    )
                            }
                            .buttonStyle(AppleFluidPressStyle())
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)
                } else {
                    optionalScrollView {
                        VStack(alignment: .leading, spacing: 9) {
                            ForEach(groupsToShow) { appGroup in
                                cleanAppTargetRow(appGroup: appGroup, categoryID: catGroup.id)
                            }
                            Spacer(minLength: 8)
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 14)
                        .padding(.bottom, 16)
                    }
                }
            } else {
                Text(L10n.selectCleanupDomainLabel(viewModel.language))
                    .foregroundStyle(InnotecTheme.inkMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .innotecLiquidGlass(
            cornerRadius: 20,
            tint: InnotecTheme.royalPurple,
            tintOpacity: 0.10,
            isInteractive: false,
            isStaticSnapshot: isStaticSnapshot,
            isElevated: true
        )
    }

    private func confidenceFilterBar(for catGroup: CleanupCategoryGroup) -> some View {
        let totalSelectedReviewCount = viewModel.report?.selectedReviewItemCount ?? 0
        let totalSelectedReviewBytes = viewModel.report?.selectedReviewBytes ?? 0

        return HStack(spacing: 8) {
            HStack(spacing: 5) {
                ForEach(ConfidenceFilter.allCases, id: \.rawValue) { filter in
                    confidenceFilterChip(filter: filter, catGroup: catGroup)
                }
            }

            Spacer(minLength: 8)

            if totalSelectedReviewCount > 0 {
                Button {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.15) : InnotecTheme.fluidSpring) {
                        viewModel.unselectAllReviewItems()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "shield.slash.fill")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(
                            "\(L10n.unselectReviewButton(viewModel.language)) (\(totalSelectedReviewCount) · \(ByteFormatter.string(from: totalSelectedReviewBytes)))"
                        )
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    }
                    .foregroundStyle(InnotecTheme.amberReview)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(InnotecTheme.amberReview.opacity(0.14))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(InnotecTheme.amberReview.opacity(0.42), lineWidth: 1.0)
                    )
                }
                .buttonStyle(AppleFluidPressStyle())
            }
        }
    }

    private func confidenceFilterChip(
        filter: ConfidenceFilter,
        catGroup: CleanupCategoryGroup
    ) -> some View {
        let isSelected = (viewModel.confidenceFilter == filter)
        let count = catGroup.appGroupCount(matching: filter)
        let activeColor: Color
        switch filter {
        case .all:
            activeColor = InnotecTheme.royalPurple
        case .safeOnly:
            activeColor = InnotecTheme.luminousMint
        case .needsReview:
            activeColor = InnotecTheme.amberReview
        }

        return Button {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : InnotecTheme.fluidSpring) {
                viewModel.setConfidenceFilter(filter)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: filter.systemSymbolName)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : activeColor)

                Text(L10n.confidenceFilterTitle(filter, viewModel.language))
                    .font(.system(size: 11, weight: isSelected ? .bold : .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? .white : InnotecTheme.inkPrimary)

                Text("\(count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .padding(.horizontal, 5.5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.white.opacity(0.24) : activeColor.opacity(0.12))
                    )
                    .foregroundStyle(isSelected ? .white : activeColor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isSelected ? activeColor : Color.white.opacity(0.75))
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? activeColor.opacity(0.9) : InnotecTheme.royalPurple.opacity(0.14),
                        lineWidth: 0.9
                    )
            )
        }
        .buttonStyle(AppleFluidPressStyle())
    }

    private func cleanAppTargetRow(
        appGroup: ApplicationBundleGroup,
        categoryID: String
    ) -> some View {
        let primaryItem = appGroup.items.first
        let isSelected = appGroup.isAllSelected || appGroup.isPartiallySelected
        let primaryConfidence = appGroup.primaryConfidence

        return HStack(alignment: .center, spacing: 14) {
            // Checkbox
            triStateCheckbox(
                isAllSelected: appGroup.isAllSelected,
                isPartiallySelected: appGroup.isPartiallySelected,
                size: 22,
                cornerRadius: 7
            ) {
                viewModel.toggleAppGroupSelection(categoryID: categoryID, appGroupID: appGroup.id)
            }

            // App / Tool Icon
            appIconView(for: appGroup.bundlePath, isSelected: isSelected)
                .frame(width: 36, height: 36)

            // Main Content: Name + Simple Badge, Abbreviated Home Path, Short Explanation
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(appGroup.appDisplayName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(InnotecTheme.inkPrimary)
                        .lineLimit(1)

                    if primaryConfidence != .safeAutoSelect {
                        confidenceBadge(for: primaryConfidence)
                    }

                    if appGroup.isRunning {
                        Text(L10n.activeBadge(viewModel.language))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(InnotecTheme.amberReview.opacity(0.14)))
                            .foregroundStyle(InnotecTheme.amberReview)
                    }
                }

                if let item = primaryItem {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(InnotecTheme.royalPurple.opacity(0.75))

                        Text(L10n.abbreviateHomePath(item.path))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(InnotecTheme.inkSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if appGroup.items.count > 1 {
                            Text("+\(appGroup.items.count - 1)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .padding(.horizontal, 5.5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(InnotecTheme.lavenderTint))
                                .foregroundStyle(InnotecTheme.royalPurple)
                        }
                    }

                    Text(item.safetyExplanation)
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(InnotecTheme.inkMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            // Right Side: Size + File Count + Reveal in Finder
            HStack(spacing: 14) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ByteFormatter.string(from: appGroup.totalAllocatedBytes))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(
                            isSelected
                                ? InnotecTheme.luminousMint
                                : InnotecTheme.inkPrimary
                        )

                    Text("\(appGroup.totalFileCount.formatted()) \(L10n.filesLabel(viewModel.language))")
                        .font(.system(size: 10.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(InnotecTheme.inkMuted)
                }

                if let item = primaryItem {
                    Button {
                        viewModel.revealInFinder(path: item.path)
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(InnotecTheme.royalPurple)
                            .frame(width: 30, height: 30)
                            .background(
                                Circle()
                                    .fill(InnotecTheme.lavenderTint.opacity(0.85))
                            )
                            .overlay(
                                Circle()
                                    .strokeBorder(InnotecTheme.royalPurple.opacity(0.25), lineWidth: 0.9)
                            )
                    }
                    .buttonStyle(AppleFluidPressStyle())
                    .help(L10n.revealInFinderButton(viewModel.language))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.94 : 0.68))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isSelected
                        ? LinearGradient(
                            colors: [
                                InnotecTheme.royalPurple.opacity(0.28),
                                InnotecTheme.mintTeal.opacity(0.42),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        : LinearGradient(
                            colors: [
                                InnotecTheme.royalPurple.opacity(0.10),
                                InnotecTheme.royalPurple.opacity(0.06),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                    lineWidth: 1.0
                )
        )
        .shadow(
            color: InnotecTheme.royalPurple.opacity(isSelected ? 0.06 : 0.02),
            radius: 6,
            x: 0,
            y: 2
        )
    }

    @ViewBuilder
    private func optionalScrollView<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if isStaticSnapshot {
            content()
        } else {
            ScrollView {
                content()
            }
            .scrollIndicators(.automatic)
        }
    }

    @ViewBuilder
    private func appIconView(for bundlePath: String?, isSelected: Bool = false) -> some View {
        if let path = bundlePath, FileManager.default.fileExists(atPath: path) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .shadow(color: InnotecTheme.royalPurple.opacity(0.14), radius: 3, x: 0, y: 1.5)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                InnotecTheme.lavenderTint,
                                InnotecTheme.mintSurfaceTint,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        InnotecTheme.royalPurple.opacity(isSelected ? 0.55 : 0.30),
                                        InnotecTheme.mintTeal.opacity(isSelected ? 0.65 : 0.40),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.0
                            )
                    )

                Image(systemName: "cube.transparent.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? InnotecTheme.royalPurple : InnotecTheme.luminousMint)
            }
        }
    }

    private func confidenceBadge(for confidence: SafetyConfidence) -> some View {
        let isSafe = (confidence == .safeAutoSelect)
        let tint = isSafe ? InnotecTheme.luminousMint : InnotecTheme.amberReview
        let bg = isSafe ? InnotecTheme.mintSurfaceTint : Color(red: 1.0, green: 0.96, blue: 0.88)
        return HStack(spacing: 4) {
            Circle()
                .fill(tint)
                .frame(width: 5.5, height: 5.5)
            Text(L10n.shortConfidenceBadge(confidence, viewModel.language))
                .font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .padding(.horizontal, 7.5)
        .padding(.vertical, 2)
        .background(Capsule().fill(bg))
        .overlay(Capsule().strokeBorder(tint.opacity(0.45), lineWidth: 0.8))
        .foregroundStyle(tint)
    }

    // MARK: - Bottom Bar: Clean Command Dock

    private var footerCommandDock: some View {
        let selectedCount = viewModel.report?.totalSelectedCount ?? 0
        let selectedBytesFormatted = ByteFormatter.string(from: viewModel.report?.selectedTotalBytes ?? 0)
        let canClean = selectedCount > 0 && !viewModel.isScanning && !viewModel.isCleaning
        let hasCleanupBanner = viewModel.lastDryRunSummary != nil

        let dockStatusText: String = {
            if let summary = viewModel.lastDryRunSummary {
                return summary
            }
            if let report = viewModel.report {
                return L10n.footerSelectionStatus(
                    duration: report.scanDurationSeconds,
                    selectedCount: selectedCount,
                    lang: viewModel.language
                )
            }
            return viewModel.statusMessage
        }()

        return HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: hasCleanupBanner ? "checkmark.seal.fill" : "checkmark.shield.fill")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(InnotecTheme.luminousMint)

                Text(dockStatusText)
                    .font(
                        .system(
                            size: 12, weight: hasCleanupBanner ? .bold : .medium,
                            design: hasCleanupBanner ? .rounded : .default)
                    )
                    .monospacedDigit()
                    .foregroundStyle(hasCleanupBanner ? InnotecTheme.inkPrimary : InnotecTheme.inkSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, hasCleanupBanner ? 12 : 0)
            .padding(.vertical, hasCleanupBanner ? 6 : 0)
            .background(
                Capsule()
                    .fill(hasCleanupBanner ? InnotecTheme.mintSurfaceTint.opacity(0.90) : Color.clear)
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        hasCleanupBanner ? InnotecTheme.luminousMint.opacity(0.45) : Color.clear,
                        lineWidth: 1.0
                    )
            )

            Spacer()

            // Primary Action Button: Permanently Clean Selected Items (single size figure in dock)
            Button {
                viewModel.performCleanup()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12.5, weight: .bold))
                    Text(
                        L10n.cleanSelectedButtonTitle(
                            count: selectedCount,
                            formattedBytes: selectedBytesFormatted,
                            language: viewModel.language
                        )
                    )
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(
                            canClean
                                ? LinearGradient(
                                    colors: [
                                        InnotecTheme.luminousMint, InnotecTheme.mintTeal, InnotecTheme.royalPurple,
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                : LinearGradient(
                                    colors: [InnotecTheme.inkMuted.opacity(0.45), InnotecTheme.inkMuted.opacity(0.35)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                        )
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(canClean ? 0.55 : 0.25), lineWidth: 1)
                )
                .shadow(
                    color: canClean ? InnotecTheme.luminousMint.opacity(0.28) : .clear,
                    radius: 8,
                    x: 0,
                    y: 3
                )
            }
            .buttonStyle(AppleFluidPressStyle())
            .disabled(!canClean)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .innotecLiquidGlass(
            cornerRadius: 16,
            tint: InnotecTheme.royalPurple,
            tintOpacity: 0.12,
            isInteractive: false,
            isStaticSnapshot: isStaticSnapshot,
            isElevated: true
        )
    }

    // MARK: - Pre-Clean Running Applications Interception Sheet

    private var runningAppConflictsModalCard: some View {
        let conflicts = viewModel.pendingRunningAppConflicts
        let totalSelectedCount = viewModel.report?.totalSelectedCount ?? 0
        let conflictItemsCount = Set(conflicts.flatMap(\.affectedItemIDs)).count
        let canSkipAndCleanRest = totalSelectedCount > conflictItemsCount

        return VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [InnotecTheme.royalPurple, InnotecTheme.luminousMint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: InnotecTheme.royalPurple.opacity(0.28), radius: 8, x: 0, y: 3)

                    Image(systemName: "power.circle.fill")
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.runningAppsModalTitle(count: conflicts.count, language: viewModel.language))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(InnotecTheme.inkPrimary)

                    Text(L10n.runningAppsModalSubtitle(viewModel.language))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(InnotecTheme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
            }

            // Running App Rows
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(conflicts) { conflict in
                        HStack(spacing: 12) {
                            appIconView(for: conflict.bundlePath)
                                .frame(width: 34, height: 34)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 7) {
                                    Text(conflict.displayName)
                                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                                        .foregroundStyle(InnotecTheme.inkPrimary)

                                    Text(L10n.activeBadge(viewModel.language))
                                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                        .padding(.horizontal, 6.5)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color(red: 1.0, green: 0.95, blue: 0.86)))
                                        .overlay(
                                            Capsule().strokeBorder(
                                                InnotecTheme.amberReview.opacity(0.45), lineWidth: 0.8)
                                        )
                                        .foregroundStyle(InnotecTheme.amberReview)
                                }

                                Text(conflict.bundleIdentifier)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(InnotecTheme.inkMuted)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text(
                                L10n.runningAppAffectedSummary(
                                    itemsCount: conflict.affectedItemsCount,
                                    formattedBytes: ByteFormatter.string(from: conflict.affectedAllocatedBytes),
                                    language: viewModel.language
                                )
                            )
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(InnotecTheme.royalPurple)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(InnotecTheme.lavenderTint))
                            .overlay(
                                Capsule().strokeBorder(InnotecTheme.royalPurple.opacity(0.22), lineWidth: 0.8)
                            )
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.92))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(InnotecTheme.royalPurple.opacity(0.16), lineWidth: 1)
                        )
                    }
                }
            }
            .frame(maxHeight: 220)

            // Action Buttons or Graceful Quit Progress
            if viewModel.isQuittingRunningApps {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.runningAppsClosingProgress(viewModel.language))
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(InnotecTheme.royalPurple)
                    Spacer()
                }
                .padding(.vertical, 6)
            } else {
                HStack(spacing: 10) {
                    Button {
                        viewModel.cancelRunningAppConflictsModal()
                    } label: {
                        Text(L10n.runningAppsCancelButton(viewModel.language))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(InnotecTheme.inkSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.white.opacity(0.90)))
                            .overlay(
                                Capsule().strokeBorder(InnotecTheme.inkMuted.opacity(0.32), lineWidth: 1)
                            )
                    }
                    .buttonStyle(AppleFluidPressStyle())

                    Spacer()

                    Button {
                        viewModel.confirmCleanWithoutClosing()
                    } label: {
                        Text(L10n.runningAppsCleanAnywayButton(viewModel.language))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(InnotecTheme.royalPurple)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(InnotecTheme.lavenderTint))
                            .overlay(
                                Capsule().strokeBorder(InnotecTheme.royalPurple.opacity(0.28), lineWidth: 1)
                            )
                    }
                    .buttonStyle(AppleFluidPressStyle())

                    if canSkipAndCleanRest {
                        Button {
                            viewModel.confirmSkipOpenAppsAndClean()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.uturn.forward.circle")
                                    .font(.system(size: 12, weight: .bold))
                                Text(L10n.runningAppsSkipButton(viewModel.language))
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(InnotecTheme.inkPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(InnotecTheme.mintSurfaceTint))
                            .overlay(
                                Capsule().strokeBorder(InnotecTheme.luminousMint.opacity(0.45), lineWidth: 1)
                            )
                        }
                        .buttonStyle(AppleFluidPressStyle())
                    }

                    Button {
                        viewModel.confirmQuitAppsAndClean()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "power.circle.fill")
                                .font(.system(size: 12.5, weight: .bold))
                            Text(L10n.runningAppsQuitAndCleanButton(viewModel.language))
                                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8.5)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            InnotecTheme.luminousMint, InnotecTheme.mintTeal, InnotecTheme.royalPurple,
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                        .overlay(
                            Capsule().strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
                        )
                        .shadow(color: InnotecTheme.royalPurple.opacity(0.24), radius: 8, x: 0, y: 3)
                    }
                    .buttonStyle(AppleFluidPressStyle())
                }
            }
        }
        .padding(24)
        .frame(width: 680)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [InnotecTheme.royalPurple.opacity(0.35), InnotecTheme.luminousMint.opacity(0.45)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .shadow(color: InnotecTheme.royalPurple.opacity(0.22), radius: 28, x: 0, y: 14)
    }
}
