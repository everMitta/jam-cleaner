## Summary

<!-- Describe what this PR changes and why. Link any related issue (e.g., Closes #123). -->

## Type of Change

- [ ] Bug fix
- [ ] New or updated cache rule (`Subscanners.swift` / `RuleKnowledgeBase.swift`)
- [ ] Safety guard enhancement (`SafetyGuardEngine` / `ExclusionPrefixTree`)
- [ ] UI / UX polish (`MainDashboardView.swift` / `InnotecTheme.swift`)
- [ ] Localization update (`Localization.swift` — `en` / `es` / `fr`)
- [ ] Documentation / CI / Build tooling

## Safety & Quality Checklist

- [ ] `swift test` passes all unit tests locally (`make test`).
- [ ] `make lint` and `make app` succeed with valid `Info.plist` and `PrivacyInfo.xcprivacy`.
- [ ] **Safety Tier Verification**: Any newly added scan target uses `.safeAutoSelect` *only* if it is 100% regenerable without losing user data, sessions, credentials, or multi-gigabyte model downloads; otherwise it uses `.reviewRecommended`.
- [ ] **Localization**: Any new user-facing string is localized across English (`en`), Spanish (`es`), and French (`fr`) in `Localization.swift`.
- [ ] **Portability**: No hardcoded local machine paths (`/Users/...`) or personal identifiers are introduced.
