# Existing PIN Unlock Navigator-First Fix Design

## 1. Goal

This design addresses the remaining Phase 1 device-validation gap called out in `第一阶段产品进度报告.md`:

- existing-PIN unlock after relaunch still has an unresolved return-chain issue on Android device/emulator;
- current success handling in `PinUnlockPage` relies on `GoRouter.canPop()` / `GoRouter.pop(true)` before trying the local `Navigator`;
- external `go_router` evidence shows known `StatefulShellRoute` / nested navigator / Android back-stack ambiguity, so `router.canPop()` is not a trustworthy primary signal in this scenario.

The goal of this slice is not to redesign routing. It is to make the unlock success path complete the original `push<bool>('/unlock/pin')` contract through the most local, least ambiguous pop mechanism first, while preserving a safe `/vault` fallback.

---

## 2. Current Problem

The relevant flow is:

1. `AppLockScreen._openPinUnlock()` opens `/unlock/pin` with `await appRouterProvider.push<bool>('/unlock/pin')`.
2. `PinUnlockPage._submit()` verifies the PIN and then decides how to leave the page.
3. The current success path checks `router.canPop()` first, then tries `router.pop(true)`, then `navigator.pop(true)`, then `router.go('/vault')`.

That order is risky for this codebase because:

- the caller is waiting for a `bool` result from a pushed page;
- the page may be hosted under a shell/nested navigator topology where the router's pop state does not match the page's owning navigator;
- `go_router` has known Android + `StatefulShellRoute` pop-semantics issues in nested navigator scenarios;
- device verification has shown the lock screen and PIN page are reachable, but the return chain remains the unstable part.

So the bug is best treated as a **return-path ownership problem**, not as a PIN verification problem.

---

## 3. Scope

### In scope

1. Strengthen the unlock success return path in `PinUnlockPage`.
2. Prefer the local navigator return contract over router-level pop preflight.
3. Keep `/vault` navigation as a last-resort escape hatch.
4. Preserve and/or refine the strongest available regression tests.
5. Re-run focused auth tests, diagnostics, `flutter analyze`, and emulator validation.

### Out of scope

1. Routing architecture redesign.
2. Replacing `AppLockGate` or `StatefulShellRoute`.
3. New back-button dispatcher infrastructure.
4. Broad navigator abstraction/refactor.
5. Unrelated auth/security changes.

---

## 4. Options Considered

### Option A: Navigator-first minimal defensive fix (recommended)

On unlock success:

1. try to complete the pushed-page contract through the local navigator first;
2. only use router pop if the local pop path cannot complete;
3. if no pop path is valid, navigate to `/vault`.

Why this is recommended:

- `AppLockGate` opened the page with `push<bool>()`, so returning through the local page owner is the most direct way to satisfy the caller contract;
- it minimizes trust in `router.canPop()` in the exact scenario where external evidence says it may be misleading;
- it is the smallest change that can improve device robustness without reworking the route model.

### Option B: Keep investigating until we have a perfect failing reproduction

This would likely improve understanding, but current evidence is already strong enough to justify a narrow defensive patch. Additional investigation is now lower-value than a minimal fix + regression pass.

### Option C: Redesign shell/back-stack ownership

This is too large for the current Phase 1 objective and would introduce more routing risk than it removes for this slice.

---

## 5. Recommended Design

### 5.1 Success-path policy

`PinUnlockPage` should no longer treat `router.canPop()` as the primary authority for completing the unlock return.

Instead, the success path should follow this policy:

1. unlock session state;
2. inspect the local `Navigator` tied to the page context;
3. if that navigator can pop, use it to return `true`;
4. otherwise, attempt the router-level pop only as a secondary path if it is clearly available;
5. otherwise, navigate to `/vault`.

This keeps the current user-visible fallback behavior, but changes the trust hierarchy to favor the pushed page's likely owner.

### 5.2 Regression strategy

The strongest current automated regression is already in:

- `test/features/auth_security/presentation/app_lock_gate_test.dart`

That test proves the lock screen can open `/unlock/pin` and return to `/vault` without throwing in the current widget topology.

Before changing production logic, we should add or tighten one regression around the success-path contract so the test reflects the navigator-first expectation instead of only final visible UI.

### 5.3 Verification strategy

After the fix:

1. focused auth widget tests must pass;
2. diagnostics for changed files must be clean;
3. `flutter analyze` must pass;
4. emulator verification must confirm the existing-PIN lock screen can open `PIN 解锁`, accept the PIN, and return cleanly through the success path without reintroducing the prior crash symptom.

---

## 6. Risks

1. A navigator-first patch could pass widget tests but still fail to deliver the expected `bool` on device if ownership is stranger than current evidence suggests.
2. A router fallback could still hide a broken return-value path if we only assert visible navigation.
3. Extra diagnostics added during investigation should be removed or reduced once the fix is validated, so this slice does not leave noisy runtime logging behind.

---

## 7. Acceptance Criteria

This slice is complete when all of the following are true:

1. `PinUnlockPage` success handling prefers the page-local pop path over router-first preflight.
2. The strongest available auth regression test is updated first and passes after the fix.
3. No auth widget regressions are introduced.
4. `flutter analyze` and diagnostics remain clean.
5. Emulator verification no longer shows the unstable existing-PIN unlock return behavior as a blocking Phase 1 device-validation gap.
