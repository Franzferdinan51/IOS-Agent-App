# Enhancement Backlog

Generated from Enhancement Hunter on 2026-07-12.

## P1 — Reliability and error-state coverage

1. Audit the 36 Swift files containing async operations; add explicit loading, empty, retry, and user-visible failure states where absent (only 5 currently expose loading state).
2. Review 174 error-handling sites, prioritising network calls whose failures are swallowed or only logged. Ensure each screen presents actionable error feedback and retry behavior.
3. Review 65 `Task {}` blocks for cancellation and error propagation; avoid detached/unstructured tasks that can outlive their view models.
4. Add lifecycle cleanup (`onAppear`/`onDisappear` or explicit start/stop APIs) to `KanbanViewModel.swift` and `DeviceControlsViewModel.swift`.

## P2 — Accessibility and UI testability

5. Add stable accessibility identifiers to interactive views in:
   - `DualAgent/Features/MainTabView.swift`
   - `DualAgent/Features/Settings/DefaultModelPickerView.swift`
   - `DualAgent/Features/Memory/MemoryView.swift`
   - `DualAgent/Features/Device/DeviceControlsView.swift`
   - `DualAgent/Features/Skills/SkillsView.swift`
   - `DualAgent/Features/Crons/CronsView.swift`
   - `DualAgent/Features/Approvals/ApprovalInboxView.swift`
   - `DualAgent/Features/Onboarding/OpenClawQRScannerView.swift`
6. Add UI-test coverage for the identifiers above and verify controls by role/identifier rather than visible decorative text.

## P3 — Configuration and maintainability

7. Centralise runtime server URL defaults and remove duplicated fallback ports from `MainTabView.swift`, `DualAgentApp.swift`, and `DirectOpenClawChatSmoke.swift`.
8. Review the 159 force-unwrap/force-cast matches not covered by the immediate crash-safety patch; distinguish intentional non-optional invariants from unsafe runtime assumptions.
9. Review the 10 views flagged as lacking an obvious ObservableObject pattern; document intentional stateless views and add observable state where network-driven UI requires it.
10. Replace placeholder preview URLs/contact links with typed URL constants or a safe Link helper.

## Findings not classified as hardcoded credentials

The scan found runtime credential plumbing via Keychain/environment variables, but no hardcoded password, token, API key, or secret value. The hardcoded URLs/ports are development fallbacks and are tracked above as configuration work.
