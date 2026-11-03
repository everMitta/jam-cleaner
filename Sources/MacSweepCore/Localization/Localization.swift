import Foundation

/// Supported UI languages for MacSweep, defaulting automatically to the computer's preferred language.
public enum AppLanguage: String, CaseIterable, Codable, Sendable, Identifiable {
    case english = "en"
    case spanish = "es"
    case french = "fr"

    public var id: String { rawValue }

    public var shortCode: String {
        rawValue.uppercased()
    }

    public var shortLabel: String {
        shortCode
    }

    public var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Español"
        case .french: return "Français"
        }
    }

    /// Detects the default language from the computer's `Locale.preferredLanguages`.
    /// Falls back to `.english` if the primary system language is not Spanish or French.
    public static func systemDefault(
        preferredLanguages: [String] = Locale.preferredLanguages,
        fallbackLanguageCode: String? = Locale.current.language.languageCode?.identifier
    ) -> AppLanguage {
        var candidates = preferredLanguages
        if let fallbackLanguageCode {
            candidates.append(fallbackLanguageCode)
        }
        for identifier in candidates {
            let normalized = identifier.lowercased()
            if normalized.hasPrefix("es") {
                return .spanish
            }
            if normalized.hasPrefix("fr") {
                return .french
            }
            if normalized.hasPrefix("en") {
                return .english
            }
        }
        return .english
    }
}

/// Centralized localization catalog for English, Spanish, and French.
public enum L10n {
    // MARK: - Pre-Scan Opening Screen

    public static func welcomeTitle(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Choose What to Scan"
        case .spanish: return "Elige qué analizar en tu Mac"
        case .french: return "Choisissez quoi analyser sur votre Mac"
        }
    }

    public static func welcomeSubtitle(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Inspect regenerable caches, build artifacts, and local runtime storage."
        case .spanish: return "Inspecciona cachés regenerables, artefactos de compilación y entornos locales."
        case .french: return "Inspectez les caches régénérables, artefacts de compilation et environnements locaux."
        }
    }

    public static func selectedBadge(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Selected"
        case .spanish: return "Seleccionado"
        case .french: return "Sélectionné"
        }
    }

    public static func unselectedBadge(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Excluded"
        case .spanish: return "Excluido"
        case .french: return "Exclu"
        }
    }

    public static func startScanButton(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Start Scan"
        case .spanish: return "Iniciar análisis"
        case .french: return "Lancer l’analyse"
        }
    }

    // MARK: - Scan Scopes (General, Developer, AI)

    public static func scopeTitle(_ scope: ScanScope, _ lang: AppLanguage) -> String {
        switch (scope, lang) {
        case (.general, .english): return "General"
        case (.general, .spanish): return "General"
        case (.general, .french): return "Général"

        case (.developer, .english): return "Developer"
        case (.developer, .spanish): return "Desarrollador"
        case (.developer, .french): return "Développeur"

        case (.ai, .english): return "AI"
        case (.ai, .spanish): return "IA"
        case (.ai, .french): return "IA"
        }
    }

    public static func scopeShortDescription(_ scope: ScanScope, _ lang: AppLanguage) -> String {
        switch (scope, lang) {
        case (.general, .english):
            return "App caches, web browsers, system logs, and broken preferences."
        case (.general, .spanish):
            return "Cachés de aplicaciones, navegadores web, registros del sistema y preferencias dañadas."
        case (.general, .french):
            return "Caches d’applications, navigateurs web, journaux système et préférences corrompues."

        case (.developer, .english):
            return "Xcode DerivedData, iOS Simulators, and toolchain build caches."
        case (.developer, .spanish):
            return "DerivedData de Xcode, simuladores de iOS y cachés de compilación."
        case (.developer, .french):
            return "DerivedData Xcode, simulateurs iOS et caches de compilation."

        case (.ai, .english):
            return "Local AI assistants, agent sandboxes, and headless browser caches."
        case (.ai, .spanish):
            return "Asistentes de IA locales, entornos de agentes y navegadores automatizados."
        case (.ai, .french):
            return "Assistants IA locaux, environnements d’agents et navigateurs automatisés."
        }
    }

    // MARK: - Cleanup Categories

    public static func categoryTitle(_ category: CleanupCategory, _ lang: AppLanguage) -> String {
        switch (category, lang) {
        case (.applicationCaches, .english): return "Application Caches"
        case (.applicationCaches, .spanish): return "Cachés de aplicaciones"
        case (.applicationCaches, .french): return "Caches d’applications"

        case (.webAndElectronCaches, .english): return "Electron & Web App Caches"
        case (.webAndElectronCaches, .spanish): return "Cachés de apps Electron y Web"
        case (.webAndElectronCaches, .french): return "Caches Electron et applications web"

        case (.developerToolchains, .english): return "Developer & Toolchain Caches"
        case (.developerToolchains, .spanish): return "Cachés de herramientas de desarrollo"
        case (.developerToolchains, .french): return "Caches d’outils de développement"

        case (.xcodeJunk, .english): return "Xcode & Simulator Data"
        case (.xcodeJunk, .spanish): return "Datos de Xcode y simuladores"
        case (.xcodeJunk, .french): return "Données Xcode et simulateurs"

        case (.aiAndAgentRuntimes, .english): return "AI & Agent Runtime Caches"
        case (.aiAndAgentRuntimes, .spanish): return "Cachés de IA y agentes"
        case (.aiAndAgentRuntimes, .french): return "Caches d’IA et d’agents"

        case (.logsAndDiagnostics, .english): return "Logs & Diagnostic Reports"
        case (.logsAndDiagnostics, .spanish): return "Registros e informes de diagnóstico"
        case (.logsAndDiagnostics, .french): return "Journaux et rapports de diagnostic"

        case (.browserCaches, .english): return "Browser Caches"
        case (.browserCaches, .spanish): return "Cachés de navegadores"
        case (.browserCaches, .french): return "Caches des navigateurs"

        case (.preferenceAndStateHygiene, .english): return "Broken Preferences & Saved States"
        case (.preferenceAndStateHygiene, .spanish): return "Preferencias dañadas y estados"
        case (.preferenceAndStateHygiene, .french): return "Préférences et états enregistrés"

        case (.installerPackages, .english): return "Aged Disk Images & Installers"
        case (.installerPackages, .spanish): return "Instaladores e imágenes de disco antiguas"
        case (.installerPackages, .french): return "Images disque et installateurs anciens"
        }
    }

    public static func categorySubtitle(_ category: CleanupCategory, _ lang: AppLanguage) -> String {
        switch (category, lang) {
        case (.applicationCaches, .english):
            return "Regenerable user & sandbox application caches in ~/Library/Caches and ~/Library/Containers"
        case (.applicationCaches, .spanish):
            return "Cachés regenerables de aplicaciones en ~/Library/Caches y ~/Library/Containers"
        case (.applicationCaches, .french):
            return "Caches d’applications régénérables dans ~/Library/Caches et ~/Library/Containers"

        case (.webAndElectronCaches, .english):
            return "Chromium GPUCache, Code Cache, and DawnWebGPUCache inside ~/Library/Application Support"
        case (.webAndElectronCaches, .spanish):
            return "GPUCache, Code Cache y DawnWebGPUCache de Chromium en ~/Library/Application Support"
        case (.webAndElectronCaches, .french):
            return "GPUCache, Code Cache et DawnWebGPUCache Chromium dans ~/Library/Application Support"

        case (.developerToolchains, .english):
            return "Build & package caches for Go, Dart/Flutter, uv, npm, Yarn, Homebrew, Cargo, Maven, and Gradle"
        case (.developerToolchains, .spanish):
            return "Cachés de compilación y paquetes para Go, Dart/Flutter, uv, npm, Yarn, Homebrew, Cargo y Gradle"
        case (.developerToolchains, .french):
            return "Caches de build et paquets pour Go, Dart/Flutter, uv, npm, Yarn, Homebrew, Cargo et Gradle"

        case (.xcodeJunk, .english):
            return "DerivedData build artifacts, iOS DeviceSupport symbols, and simulator caches"
        case (.xcodeJunk, .spanish):
            return "Artefactos de compilación DerivedData, símbolos iOS DeviceSupport y cachés de simuladores"
        case (.xcodeJunk, .french):
            return "Artefacts de build DerivedData, symboles iOS DeviceSupport et caches de simulateurs"

        case (.aiAndAgentRuntimes, .english):
            return "Claude Desktop, Antigravity IDE, codex-runtimes, Chrome DevTools MCP, and Puppeteer caches"
        case (.aiAndAgentRuntimes, .spanish):
            return "Cachés de Claude Desktop, Antigravity IDE, codex-runtimes, Chrome DevTools MCP y Puppeteer"
        case (.aiAndAgentRuntimes, .french):
            return "Caches de Claude Desktop, Antigravity IDE, codex-runtimes, Chrome DevTools MCP et Puppeteer"

        case (.logsAndDiagnostics, .english):
            return "Rotational application logs, crash reports, and system diagnostic traces"
        case (.logsAndDiagnostics, .spanish):
            return "Registros de aplicaciones, informes de fallos y trazas de diagnóstico del sistema"
        case (.logsAndDiagnostics, .french):
            return "Journaux d’applications, rapports de plantage et traces de diagnostic système"

        case (.browserCaches, .english):
            return "Multi-profile HTTP/media caches for Safari, Chrome, Brave, Edge, Arc, and Firefox"
        case (.browserCaches, .spanish):
            return "Cachés multimedia y HTTP multiperfil para Safari, Chrome, Brave, Edge, Arc y Firefox"
        case (.browserCaches, .french):
            return "Caches HTTP et médias multi-profils pour Safari, Chrome, Brave, Edge, Arc et Firefox"

        case (.preferenceAndStateHygiene, .english):
            return "Corrupted .plist files and stale window restoration states for closed apps"
        case (.preferenceAndStateHygiene, .spanish):
            return "Archivos .plist dañados y estados de restauración de ventanas de apps cerradas"
        case (.preferenceAndStateHygiene, .french):
            return "Fichiers .plist corrompus et états de restauration des fenêtres d’applications fermées"

        case (.installerPackages, .english):
            return "Disk images (.dmg/.pkg) older than 30 days in ~/Downloads (never touches user documents)"
        case (.installerPackages, .spanish):
            return "Imágenes de disco (.dmg/.pkg) de más de 30 días en ~/Downloads (protege tus documentos)"
        case (.installerPackages, .french):
            return "Images disque (.dmg/.pkg) de plus de 30 jours dans ~/Downloads (protège vos documents)"
        }
    }

    // MARK: - Results Inspector Header & Columns

    public static func kpiTotalDiscovered(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "TOTAL DISCOVERED"
        case .spanish: return "TOTAL DETECTADO"
        case .french: return "TOTAL DÉTECTÉ"
        }
    }

    public static func kpiGroupsAndFiles(_ groups: Int, _ files: String, _ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "\(groups) groups • \(files) files"
        case .spanish: return "\(groups) grupos • \(files) archivos"
        case .french: return "\(groups) groupes • \(files) fichiers"
        }
    }

    public static func kpiSafeAutoSelected(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "SAFE AUTO-SELECTED"
        case .spanish: return "SEGURO (AUTOSELECCIONADO)"
        case .french: return "SÛR (SÉLECTION AUTO)"
        }
    }

    public static func kpiRegenerableSub(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "100% Regenerable Caches"
        case .spanish: return "Cachés 100% regenerables"
        case .french: return "Caches 100 % régénérables"
        }
    }

    public static func kpiOptionalReview(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "OPTIONAL REVIEW"
        case .spanish: return "REVISIÓN OPCIONAL"
        case .french: return "RÉVISION OPTIONNELLE"
        }
    }

    public static func kpiReviewSub(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Simulator Apps & Browsers"
        case .spanish: return "Apps de simulador y navegadores"
        case .french: return "Apps simulateur et navigateurs"
        }
    }

    public static func kpiSafetyGuards(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "SAFETY GUARDS"
        case .spanish: return "PROTECCIÓN ACTIVA"
        case .french: return "GARDES DE SÉCURITÉ"
        }
    }

    public static func kpiGuardedValue(_ count: Int, _ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "\(count) Guarded"
        case .spanish: return "\(count) Protegidos"
        case .french: return "\(count) Protégés"
        }
    }

    public static func kpiActiveAppsProtected(_ count: Int, _ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "\(count) Active Apps Protected"
        case .spanish: return "\(count) apps activas protegidas"
        case .french: return "\(count) apps actives protégées"
        }
    }

    public static func scopesButtonTitle(_ active: Int, _ total: Int, _ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Scopes (\(active)/\(total))"
        case .spanish: return "Áreas (\(active)/\(total))"
        case .french: return "Domaines (\(active)/\(total))"
        }
    }

    public static func rescanButtonTitle(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Rescan"
        case .spanish: return "Reanalizar"
        case .french: return "Réanalyser"
        }
    }

    public static func cleanupDomainsHeader(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Categories"
        case .spanish: return "Categorías"
        case .french: return "Catégories"
        }
    }

    public static func activeCountBadge(_ count: Int, _ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "\(count) ACTIVE"
        case .spanish: return "\(count) ACTIVAS"
        case .french: return "\(count) ACTIFS"
        }
    }

    public static func groupsAndSafeSummary(_ groups: Int, _ safeStr: String, _ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "\(groups) groups • \(safeStr) safe"
        case .spanish: return "\(groups) grupos • \(safeStr) seguro"
        case .french: return "\(groups) groupes • \(safeStr) sûr"
        }
    }

    public static func bundlesCountBadge(_ count: Int, _ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "\(count) BUNDLES"
        case .spanish: return "\(count) PAQUETES"
        case .french: return "\(count) PAQUETS"
        }
    }

    public static func filterSearchPlaceholder(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Filter bundles, toolchains, or paths..."
        case .spanish: return "Filtrar paquetes, herramientas o rutas..."
        case .french: return "Filtrer les paquets, outils ou chemins..."
        }
    }

    public static func filesCountLabel(_ countStr: String, _ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "\(countStr) files"
        case .spanish: return "\(countStr) archivos"
        case .french: return "\(countStr) fichiers"
        }
    }

    public static func targetsCountLabel(_ count: Int, _ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "\(count) target(s)"
        case .spanish: return "\(count) elemento(s)"
        case .french: return "\(count) cible(s)"
        }
    }

    public static func selectedOverTotalVolume(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "SELECTED / TOTAL VOLUME"
        case .spanish: return "VOLUMEN SELECCIONADO / TOTAL"
        case .french: return "VOLUME SÉLECTIONNÉ / TOTAL"
        }
    }

    public static func inspectableFilesystemTargets(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "INSPECTABLE FILESYSTEM TARGETS"
        case .spanish: return "RUTAS DEL SISTEMA DE ARCHIVOS"
        case .french: return "CIBLES DU SYSTÈME DE FICHIERS"
        }
    }

    public static func revealInFinder(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Reveal in Finder"
        case .spanish: return "Mostrar en Finder"
        case .french: return "Afficher dans le Finder"
        }
    }

    public static func additionalTargetsHeader(_ categoryTitle: String, _ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "ADDITIONAL TARGETS IN \(categoryTitle.uppercased())"
        case .spanish: return "OTROS ELEMENTOS EN \(categoryTitle.uppercased())"
        case .french: return "AUTRES CIBLES DANS \(categoryTitle.uppercased())"
        }
    }

    public static func clickAnyTargetToInspect(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Click any target to inspect"
        case .spanish: return "Haz clic para inspeccionar"
        case .french: return "Cliquez pour inspecter"
        }
    }

    public static func confidenceBadge(_ confidence: SafetyConfidence, _ lang: AppLanguage) -> String {
        switch (confidence, lang) {
        case (.safeAutoSelect, .english): return "Safe (Auto-Selected)"
        case (.safeAutoSelect, .spanish): return "Seguro (Autoseleccionado)"
        case (.safeAutoSelect, .french): return "Sûr (Sélection auto)"

        case (.reviewRecommended, .english): return "Review Recommended"
        case (.reviewRecommended, .spanish): return "Revisión recomendada"
        case (.reviewRecommended, .french): return "Révision recommandée"

        case (.blocked, .english): return "Blocked by Safety Guard"
        case (.blocked, .spanish): return "Bloqueado por seguridad"
        case (.blocked, .french): return "Bloqué par sécurité"
        }
    }

    public static func runningAppBadge(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Running App"
        case .spanish: return "App en ejecución"
        case .french: return "App active"
        }
    }

    public static func selectedForPreview(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "SELECTED FOR CLEANUP"
        case .spanish: return "SELECCIONADO PARA LIMPIAR"
        case .french: return "SÉLECTIONNÉ POUR NETTOYAGE"
        }
    }

    public static func verifySafetyGuardsDryRun(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Verify Safety Guards (Dry-Run)"
        case .spanish: return "Verificar protección (Simulación)"
        case .french: return "Vérifier la sécurité (Simulation)"
        }
    }

    public static func statusReadyToScan(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Select your inspection scopes to begin"
        case .spanish: return "Selecciona las áreas para comenzar"
        case .french: return "Sélectionnez vos domaines pour commencer"
        }
    }

    public static func statusScanning(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Scanning selected domains with 4-layer safety guards…"
        case .spanish: return "Analizando áreas seleccionadas con protección de 4 capas…"
        case .french: return "Analyse des domaines sélectionnés avec protection 4 couches…"
        }
    }

    public static func statusCompleted(
        duration: Double,
        guardedCount: Int,
        activeScopes: Int,
        totalScopes: Int,
        lang: AppLanguage
    ) -> String {
        switch lang {
        case .english:
            return String(format: "Scanned in %.2fs", duration)
        case .spanish:
            return String(format: "Analizado en %.2fs", duration)
        case .french:
            return String(format: "Analysé en %.2fs", duration)
        }
    }

    public static func footerSelectionStatus(
        duration: Double,
        selectedCount: Int,
        lang: AppLanguage
    ) -> String {
        let base = statusCompleted(
            duration: duration,
            guardedCount: 0,
            activeScopes: 0,
            totalScopes: 0,
            lang: lang
        )
        switch lang {
        case .english:
            let sel =
                selectedCount == 0
                ? "No items selected"
                : (selectedCount == 1 ? "1 item selected" : "\(selectedCount) items selected")
            return "\(base) · \(sel)"
        case .spanish:
            let sel =
                selectedCount == 0
                ? "Sin elementos seleccionados"
                : (selectedCount == 1 ? "1 elemento seleccionado" : "\(selectedCount) elementos seleccionados")
            return "\(base) · \(sel)"
        case .french:
            let sel =
                selectedCount == 0
                ? "Aucun élément sélectionné"
                : (selectedCount == 1 ? "1 élément sélectionné" : "\(selectedCount) éléments sélectionnés")
            return "\(base) · \(sel)"
        }
    }

    // MARK: - Dashboard View Helpers

    public static func scanCompletedStatus(
        language: AppLanguage,
        duration: Double,
        guardedCount: Int,
        activeScopes: Int,
        totalScopes: Int
    ) -> String {
        statusCompleted(
            duration: duration,
            guardedCount: guardedCount,
            activeScopes: activeScopes,
            totalScopes: totalScopes,
            lang: language
        )
    }

    public static func selectScopesToBegin(_ lang: AppLanguage) -> String {
        statusReadyToScan(lang)
    }

    public static func initializingScanStatus(language: AppLanguage, scopes: String) -> String {
        switch language {
        case .english:
            return "Initializing parallel scan for [\(scopes)] with 4-layer safety guards…"
        case .spanish:
            return "Iniciando análisis en paralelo para [\(scopes)] con protección de 4 capas…"
        case .french:
            return "Initialisation de l’analyse parallèle pour [\(scopes)] avec protection 4 couches…"
        }
    }

    public static func dryRunVerifiedStatus(
        language: AppLanguage,
        itemsCount: Int,
        formattedBytes: String
    ) -> String {
        switch language {
        case .english:
            return
                "Dry-Run Verified: \(itemsCount) items (\(formattedBytes)) passed all 4 safety layers (0 files deleted)."
        case .spanish:
            return
                "Simulación verificada: \(itemsCount) elementos (\(formattedBytes)) superaron las 4 capas de seguridad (0 archivos borrados)."
        case .french:
            return
                "Simulation vérifiée : \(itemsCount) éléments (\(formattedBytes)) ont validé les 4 couches de sécurité (0 fichier supprimé)."
        }
    }

    public static func nonDestructivePreviewCaption(_ lang: AppLanguage) -> String {
        switch lang {
        case .english:
            return "Non-destructive preview • Zero files deleted without explicit confirmation"
        case .spanish:
            return "Vista previa no destructiva • Ningún archivo se elimina sin confirmación"
        case .french:
            return "Aperçu non destructif • Aucun fichier supprimé sans confirmation"
        }
    }

    public static func totalDiscoveredTitle(_ lang: AppLanguage) -> String {
        kpiTotalDiscovered(lang)
    }

    public static func groupsLabel(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "groups"
        case .spanish: return "grupos"
        case .french: return "groupes"
        }
    }

    public static func filesLabel(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "files"
        case .spanish: return "archivos"
        case .french: return "fichiers"
        }
    }

    public static func safeLabel(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "safe"
        case .spanish: return "seguro"
        case .french: return "sûr"
        }
    }

    public static func safeAutoSelectedTitle(_ lang: AppLanguage) -> String {
        kpiSafeAutoSelected(lang)
    }

    public static func regenerableCachesSubtitle(_ lang: AppLanguage) -> String {
        kpiRegenerableSub(lang)
    }

    public static func optionalReviewTitle(_ lang: AppLanguage) -> String {
        kpiOptionalReview(lang)
    }

    public static func simulatorAndBrowsersSubtitle(_ lang: AppLanguage) -> String {
        kpiReviewSub(lang)
    }

    public static func safetyGuardsTitle(_ lang: AppLanguage) -> String {
        kpiSafetyGuards(lang)
    }

    public static func guardedWord(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Guarded"
        case .spanish: return "Protegidos"
        case .french: return "Protégés"
        }
    }

    public static func activeAppsProtectedWord(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Active Apps Protected"
        case .spanish: return "apps activas protegidas"
        case .french: return "apps actives protégées"
        }
    }

    public static func scopesButton(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Scopes"
        case .spanish: return "Áreas"
        case .french: return "Domaines"
        }
    }

    public static func scanningButton(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Scanning…"
        case .spanish: return "Analizando…"
        case .french: return "Analyse…"
        }
    }

    public static func rescanButton(_ lang: AppLanguage) -> String {
        rescanButtonTitle(lang)
    }

    public static func activeBadge(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Running"
        case .spanish: return "En ejecución"
        case .french: return "En cours"
        }
    }

    public static func scanningFilesystemLabel(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Scanning filesystem…"
        case .spanish: return "Analizando el sistema de archivos…"
        case .french: return "Analyse du système de fichiers…"
        }
    }

    public static func bundlesLabel(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "BUNDLES"
        case .spanish: return "PAQUETES"
        case .french: return "PAQUETS"
        }
    }

    public static func filterPlaceholder(_ lang: AppLanguage) -> String {
        filterSearchPlaceholder(lang)
    }

    public static func selectCleanupDomainLabel(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Select a cleanup domain"
        case .spanish: return "Selecciona una categoría de limpieza"
        case .french: return "Sélectionnez un domaine de nettoyage"
        }
    }

    public static func runningProcessGuardedLabel(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Running Process Guarded"
        case .spanish: return "Proceso activo protegido"
        case .french: return "Processus actif protégé"
        }
    }

    public static func targetsWord(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "target(s)"
        case .spanish: return "elemento(s)"
        case .french: return "cible(s)"
        }
    }

    public static func selectedTotalVolumeHeader(_ lang: AppLanguage) -> String {
        selectedOverTotalVolume(lang)
    }

    public static func inspectableTargetsHeader(_ lang: AppLanguage) -> String {
        inspectableFilesystemTargets(lang)
    }

    public static func additionalTargetsHeader(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "ADDITIONAL TARGETS IN"
        case .spanish: return "OTROS ELEMENTOS EN"
        case .french: return "AUTRES CIBLES DANS"
        }
    }

    public static func clickToInspectLabel(_ lang: AppLanguage) -> String {
        clickAnyTargetToInspect(lang)
    }

    public static func selectBundleLabel(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Select an application bundle to inspect filesystem paths"
        case .spanish: return "Selecciona un paquete de aplicación para inspeccionar sus rutas"
        case .french: return "Sélectionnez un paquet d’application pour inspecter ses chemins"
        }
    }

    public static func revealInFinderButton(_ lang: AppLanguage) -> String {
        revealInFinder(lang)
    }

    public static func posixHeuristicBadge(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "POSIX Heuristic"
        case .spanish: return "Heurística POSIX"
        case .french: return "Heuristique POSIX"
        }
    }

    public static func ruleEngineBadge(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Rule Engine"
        case .spanish: return "Motor de reglas"
        case .french: return "Moteur de règles"
        }
    }

    public static func selectedForPreviewLabel(_ lang: AppLanguage) -> String {
        selectedForPreview(lang)
    }

    public static func verifyDryRunButton(_ lang: AppLanguage) -> String {
        verifySafetyGuardsDryRun(lang)
    }

    // MARK: - Clean 2-Column Results Screen Helpers

    public static func summaryTotalLabel(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Total Found"
        case .spanish: return "Total detectado"
        case .french: return "Total détecté"
        }
    }

    public static func summarySafeLabel(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Safe to Clean"
        case .spanish: return "Seguro"
        case .french: return "Sûr"
        }
    }

    public static func summaryReviewLabel(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Needs Review"
        case .spanish: return "Revisión"
        case .french: return "À vérifier"
        }
    }

    public static func shortConfidenceBadge(_ confidence: SafetyConfidence, _ lang: AppLanguage) -> String {
        switch (confidence, lang) {
        case (.safeAutoSelect, .english): return "Safe"
        case (.safeAutoSelect, .spanish): return "Seguro"
        case (.safeAutoSelect, .french): return "Sûr"

        case (.reviewRecommended, .english): return "Review"
        case (.reviewRecommended, .spanish): return "Revisar"
        case (.reviewRecommended, .french): return "Vérifier"

        case (.blocked, .english): return "Guarded"
        case (.blocked, .spanish): return "Protegido"
        case (.blocked, .french): return "Protégé"
        }
    }

    public static func confidenceFilterTitle(_ filter: ConfidenceFilter, _ lang: AppLanguage) -> String {
        switch (filter, lang) {
        case (.all, .english): return "All"
        case (.all, .spanish): return "Todos"
        case (.all, .french): return "Tous"

        case (.safeOnly, .english): return "Safe"
        case (.safeOnly, .spanish): return "Seguro"
        case (.safeOnly, .french): return "Sûr"

        case (.needsReview, .english): return "Needs Review"
        case (.needsReview, .spanish): return "Revisión"
        case (.needsReview, .french): return "À vérifier"
        }
    }

    public static func unselectReviewButton(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Unselect Review"
        case .spanish: return "Desmarcar revisión"
        case .french: return "Désélectionner à vérifier"
        }
    }

    public static func noMatchingFilterItemsLabel(_ filter: ConfidenceFilter, _ lang: AppLanguage) -> String {
        switch (filter, lang) {
        case (.needsReview, .english):
            return "No items requiring review in this category."
        case (.needsReview, .spanish):
            return "No hay elementos que requieran revisión en esta categoría."
        case (.needsReview, .french):
            return "Aucun élément nécessitant une vérification dans cette catégorie."

        case (.safeOnly, .english):
            return "No safe auto-selected items in this category."
        case (.safeOnly, .spanish):
            return "No hay elementos seguros autoseleccionados en esta categoría."
        case (.safeOnly, .french):
            return "Aucun élément sûr sélectionné automatiquement dans cette catégorie."

        case (.all, .english):
            return "No matching items found."
        case (.all, .spanish):
            return "No se encontraron elementos que coincidan."
        case (.all, .french):
            return "Aucun élément correspondant trouvé."
        }
    }

    public static func showAllItemsButton(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Show All Items"
        case .spanish: return "Mostrar todos"
        case .french: return "Tout afficher"
        }
    }

    public static func itemsCountBadge(_ count: Int, _ lang: AppLanguage) -> String {
        switch lang {
        case .english: return count == 1 ? "1 item" : "\(count) items"
        case .spanish: return count == 1 ? "1 elemento" : "\(count) elementos"
        case .french: return count == 1 ? "1 élément" : "\(count) éléments"
        }
    }

    public static func selectedOfTotalSummary(_ selected: String, _ total: String, _ lang: AppLanguage) -> String {
        if selected == total {
            return total
        }
        return "\(selected) / \(total)"
    }

    public static func cleanFilterPlaceholder(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Filter items or paths…"
        case .spanish: return "Filtrar elementos o rutas…"
        case .french: return "Filtrer les éléments ou chemins…"
        }
    }

    public static func abbreviateHomePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        if let range = path.range(of: #"^/Users/[^/]+"#, options: .regularExpression) {
            return "~" + path[range.upperBound...]
        }
        return path
    }

    // MARK: - Live Scanning Progress Screen Helpers

    public static func scanningInProgressTitle(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Scanning Your Mac…"
        case .spanish: return "Analizando tu Mac…"
        case .french: return "Analyse de votre Mac…"
        }
    }

    public static func scanningInProgressSubtitle(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Measuring allocated APFS blocks across selected scopes"
        case .spanish: return "Calculando bloques APFS asignados en las áreas seleccionadas"
        case .french: return "Mesure des blocs APFS alloués dans les domaines sélectionnés"
        }
    }

    public static func scanningElapsedBadge(seconds: Double, language lang: AppLanguage) -> String {
        switch lang {
        case .english: return String(format: "%.1fs elapsed", seconds)
        case .spanish: return String(format: "%.1fs transcurridos", seconds)
        case .french: return String(format: "%.1fs écoulées", seconds)
        }
    }

    public static func localizedProgressStage(_ rawStage: String, language lang: AppLanguage) -> String {
        guard lang != .english else { return rawStage }
        if rawStage == "Scan complete." {
            return lang == .spanish ? "Análisis completado." : "Analyse terminée."
        }
        if rawStage.hasPrefix("Indexing installed applications") {
            return lang == .spanish
                ? "Indexando aplicaciones instaladas y procesos activos…"
                : "Indexation des applications installées et processus actifs…"
        }
        if rawStage.hasPrefix("Launching ") {
            return lang == .spanish
                ? "Ejecutando módulos de inspección de almacenamiento en paralelo…"
                : "Lancement des modules d’inspection du stockage en parallèle…"
        }
        if rawStage.hasPrefix("Scanning ") {
            let module = rawStage.replacingOccurrences(of: "Scanning ", with: "")
            return lang == .spanish
                ? "Analizando módulo \(module)"
                : "Analyse du module \(module)"
        }
        if rawStage.hasPrefix("Completed ") {
            let rest = rawStage.replacingOccurrences(of: "Completed ", with: "")
            return lang == .spanish
                ? "Completado: \(rest)"
                : "Terminé : \(rest)"
        }
        if rawStage.hasPrefix("Aggregating ") {
            return lang == .spanish
                ? "Agrupando detecciones en jerarquía de 3 niveles…"
                : "Agrégation des détections dans la hiérarchie à 3 niveaux…"
        }
        return rawStage
    }

    // MARK: - Live Cleaning (Move to Trash) Progress & Dock Helpers

    public static func cleanSelectedButtonTitle(
        count: Int,
        formattedBytes: String,
        language lang: AppLanguage
    ) -> String {
        if count <= 0 {
            switch lang {
            case .english: return "Clean"
            case .spanish: return "Limpiar"
            case .french: return "Nettoyer"
            }
        }
        switch lang {
        case .english: return "Clean \(formattedBytes)"
        case .spanish: return "Limpiar \(formattedBytes)"
        case .french: return "Nettoyer \(formattedBytes)"
        }
    }

    public static func cleaningInProgressTitle(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Cleaning Selected Storage…"
        case .spanish: return "Limpiando almacenamiento seleccionado…"
        case .french: return "Nettoyage de l’espace sélectionné…"
        }
    }

    public static func cleaningInProgressSubtitle(_ lang: AppLanguage) -> String {
        switch lang {
        case .english:
            return "Removing selected cache directories and reclaiming APFS disk space"
        case .spanish:
            return "Eliminando los directorios de caché seleccionados y liberando espacio APFS"
        case .french:
            return "Suppression des caches sélectionnés et libération de l’espace APFS"
        }
    }

    public static func cleaningCurrentItemLabel(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "CLEANING STORAGE"
        case .spanish: return "LIMPIANDO ALMACENAMIENTO"
        case .french: return "NETTOYAGE EN COURS"
        }
    }

    public static func cleaningGuardPillTrash(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Immediate APFS Space Reclamation"
        case .spanish: return "Liberación inmediata de espacio APFS"
        case .french: return "Libération immédiate d’espace APFS"
        }
    }

    public static func cleaningGuardPillProtected(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "4-Layer Path Guards Active"
        case .spanish: return "Protección de 4 capas activa"
        case .french: return "Protection à 4 niveaux active"
        }
    }

    public static func cleanupCompletedStatus(
        language lang: AppLanguage,
        movedCount: Int,
        formattedBytes: String,
        skippedCount: Int,
        errorCount: Int
    ) -> String {
        switch lang {
        case .english:
            var msg = "Cleaned \(movedCount) item(s) (\(formattedBytes) reclaimed)."
            if skippedCount > 0 { msg += " \(skippedCount) protected path(s) guarded." }
            if errorCount > 0 { msg += " \(errorCount) item(s) could not be removed." }
            return msg
        case .spanish:
            var msg = "Se limpiaron \(movedCount) elemento(s) (\(formattedBytes) liberados)."
            if skippedCount > 0 { msg += " \(skippedCount) ruta(s) protegida(s)." }
            if errorCount > 0 { msg += " \(errorCount) elemento(s) no se pudieron eliminar." }
            return msg
        case .french:
            var msg = "\(movedCount) élément(s) nettoyé(s) (\(formattedBytes) libérés)."
            if skippedCount > 0 { msg += " \(skippedCount) chemin(s) protégé(s)." }
            if errorCount > 0 { msg += " \(errorCount) élément(s) non supprimé(s)." }
            return msg
        }
    }

    // MARK: - Pre-Clean Running Applications Interception Sheet

    public static func runningAppsModalTitle(count: Int, language lang: AppLanguage) -> String {
        switch lang {
        case .english:
            return count == 1
                ? "1 Running Application Uses Selected Caches"
                : "\(count) Running Applications Use Selected Caches"
        case .spanish:
            return count == 1
                ? "1 aplicación abierta utiliza cachés seleccionados"
                : "\(count) aplicaciones abiertas utilizan cachés seleccionados"
        case .french:
            return count == 1
                ? "1 application ouverte utilise des caches sélectionnés"
                : "\(count) applications ouvertes utilisent des caches sélectionnés"
        }
    }

    public static func runningAppsModalSubtitle(_ lang: AppLanguage) -> String {
        switch lang {
        case .english:
            return
                "Open browsers and desktop apps keep active memory-mapped (mmap), SQLite, and GPU cache locks. Closing them gracefully before cleaning guarantees full APFS space reclamation and prevents open apps from rewriting their in-memory cache on exit."
        case .spanish:
            return
                "Los navegadores y aplicaciones abiertas mantienen bloqueos activos de memoria (mmap), SQLite y GPU. Cerrarlas antes de limpiar garantiza la liberación total del espacio APFS y evita que vuelvan a escribir su caché al salir."
        case .french:
            return
                "Les navigateurs et applications ouvertes maintiennent des verrous actifs (mmap, SQLite et GPU). Les fermer avant le nettoyage garantit la libération complète de l’espace APFS et évite la réécriture du cache à la fermeture."
        }
    }

    public static func runningAppsQuitAndCleanButton(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Quit Apps & Clean"
        case .spanish: return "Cerrar apps y limpiar"
        case .french: return "Quitter les apps et nettoyer"
        }
    }

    public static func runningAppsSkipButton(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Skip Open Apps & Clean Rest"
        case .spanish: return "Omitir apps abiertas y limpiar el resto"
        case .french: return "Ignorer les apps ouvertes et nettoyer le reste"
        }
    }

    public static func runningAppsCleanAnywayButton(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Clean Without Closing"
        case .spanish: return "Limpiar sin cerrar"
        case .french: return "Nettoyer sans fermer"
        }
    }

    public static func runningAppsCancelButton(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Cancel"
        case .spanish: return "Cancelar"
        case .french: return "Annuler"
        }
    }

    public static func runningAppsClosingProgress(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Gracefully closing selected applications…"
        case .spanish: return "Cerrando aplicaciones seleccionadas de forma segura…"
        case .french: return "Fermeture sécurisée des applications sélectionnées…"
        }
    }

    public static func runningAppAffectedSummary(
        itemsCount: Int, formattedBytes: String, language lang: AppLanguage
    ) -> String {
        switch lang {
        case .english:
            return "\(itemsCount) selected item(s) • \(formattedBytes)"
        case .spanish:
            return "\(itemsCount) elemento(s) seleccionado(s) • \(formattedBytes)"
        case .french:
            return "\(itemsCount) élément(s) sélectionné(s) • \(formattedBytes)"
        }
    }

    // MARK: - Full Disk Access (TCC) Status & System Settings Helper

    public static func fullDiskAccessGrantedBadge(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Full Disk Access Active"
        case .spanish: return "Acceso total al disco activo"
        case .french: return "Accès complet au disque actif"
        }
    }

    public static func fullDiskAccessOptionalPrompt(_ lang: AppLanguage) -> String {
        switch lang {
        case .english: return "Grant Full Disk Access for Safari & System Caches"
        case .spanish: return "Conceder Acceso total al disco para Safari y cachés del sistema"
        case .french: return "Autoriser l’accès complet au disque pour Safari et caches système"
        }
    }

    public static func fullDiskAccessTooltip(_ lang: AppLanguage) -> String {
        switch lang {
        case .english:
            return
                "Opens macOS System Settings › Privacy & Security › Full Disk Access so JAM Cleaner can inspect TCC-protected caches such as Safari."
        case .spanish:
            return
                "Abre Ajustes del Sistema › Privacidad y seguridad › Acceso total al disco para inspeccionar cachés protegidos como Safari."
        case .french:
            return
                "Ouvre Réglages Système › Confidentialité et sécurité › Accès complet au disque pour inspecter les caches protégés comme Safari."
        }
    }
}
