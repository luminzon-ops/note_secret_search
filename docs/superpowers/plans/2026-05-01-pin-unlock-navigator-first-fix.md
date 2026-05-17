# Existing PIN Unlock Navigator-First Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the existing-PIN unlock success path complete through the most local navigator first, reducing shell/router pop ambiguity on Android relaunch flows while preserving a safe `/vault` fallback.

**Architecture:** Keep `AppLockGate` and the route model unchanged. Adjust only the success return path in `PinUnlockPage`, reinforce the strongest auth regression first, and then verify with focused tests plus emulator regression.

**Tech Stack:** Flutter, Dart, Riverpod, go_router, flutter_test, Android emulator (`adb`).

---

## File Map

### Existing files to modify
- `lib/features/auth_security/presentation/pin_unlock_page.dart`
- `test/features/auth_security/presentation/app_lock_gate_test.dart`

### Existing files to verify
- `test/features/auth_security/presentation/pin_unlock_page_test.dart`
- `lib/features/auth_security/presentation/app_lock_gate.dart`
- `lib/app/router/app_router.dart`

### Docs created in this slice
- `docs/superpowers/specs/2026-05-01-pin-unlock-navigator-first-design.md`
- `docs/superpowers/plans/2026-05-01-pin-unlock-navigator-first-fix.md`

---

### Task 1: Tighten the lock-gate regression before production changes

**Files:**
- Modify: `test/features/auth_security/presentation/app_lock_gate_test.dart`
- Verify: `lib/features/auth_security/presentation/app_lock_gate.dart`
- Verify: `lib/features/auth_security/presentation/pin_unlock_page.dart`

- [ ] **Step 1: Update the strongest regression to focus on the unlock-return contract**

Keep the existing lock-screen flow test and strengthen its intent so it proves the page opened from `AppLockGate` can complete unlock without navigation exceptions and can resolve back to the caller flow.

Target existing test block:

```dart
testWidgets('existing pin unlock from lock screen returns to vault without navigation error', (
  tester,
) async {
  ...
});
```

Expected assertions to preserve or strengthen:

```dart
expect(tester.takeException(), isNull);
expect(sessionController.state.isUnlocked, isTrue);
expect(find.text('vault'), findsOneWidget);
```

- [ ] **Step 2: Run the focused lock-gate test to confirm current behavior before implementation**

Run:

```powershell
flutter test test/features/auth_security/presentation/app_lock_gate_test.dart --plain-name "existing pin unlock from lock screen returns to vault without navigation error"
```

Expected: PASS on current widget topology, confirming this is a regression guard but not yet a failing reproduction of the device-only path.

- [ ] **Step 3: Do not broaden the test matrix yet**

Do not add unrelated auth scenarios in this slice. Keep the test surface focused on the approved A-scheme fix.

---

### Task 2: Implement the navigator-first minimal defensive fix

**Files:**
- Modify: `lib/features/auth_security/presentation/pin_unlock_page.dart`

- [ ] **Step 1: Keep the success-path change isolated to `_submit()`**

The only production behavior change in this slice should happen inside:

```dart
Future<void> _submit() async {
  ...
}
```

Do not refactor `AppLockGate`, router configuration, or shell structure in this slice.

- [ ] **Step 2: Replace router-first success exit ordering with navigator-first ordering**

Implementation intent:

1. preserve successful PIN verification and session unlock;
2. prefer the local `Navigator.of(context)` pop path first;
3. only use router-level pop as a secondary path;
4. keep `router.go('/vault')` as the last-resort fallback.

Target shape:

```dart
final router = GoRouter.maybeOf(context);
final navigator = Navigator.of(context);

if (navigator.canPop()) {
  navigator.pop(true);
} else if (router != null && router.canPop()) {
  router.pop(true);
} else if (router != null) {
  router.go('/vault');
}
```

If existing temporary diagnostics remain necessary for immediate verification, keep them only if they do not alter control flow beyond logging. If they are no longer needed for this slice, remove the extra instrumentation while making the minimal logic change.

- [ ] **Step 3: Keep fallback behavior minimal**

Do not introduce new route abstractions, dispatcher changes, or back-stack helpers. This slice is strictly a local success-path hardening change.

---

### Task 3: Verify focused auth regressions and diagnostics

**Files:**
- Verify: `test/features/auth_security/presentation/app_lock_gate_test.dart`
- Verify: `test/features/auth_security/presentation/pin_unlock_page_test.dart`
- Verify: `lib/features/auth_security/presentation/pin_unlock_page.dart`

- [ ] **Step 1: Run focused auth widget tests**

Run:

```powershell
flutter test test/features/auth_security/presentation/app_lock_gate_test.dart
flutter test test/features/auth_security/presentation/pin_unlock_page_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run diagnostics on the changed file**

Run diagnostics on:

```text
lib/features/auth_security/presentation/pin_unlock_page.dart
```

Expected: no new diagnostics.

- [ ] **Step 3: Run static analysis**

Run:

```powershell
flutter analyze
```

Expected: no new issues.

---

### Task 4: Re-run the emulator existing-PIN unlock regression

**Files:**
- Verify runtime behavior via emulator only

- [ ] **Step 1: Build the debug APK if needed**

Run:

```powershell
flutter build apk --debug
```

Expected: APK builds successfully.

- [ ] **Step 2: Install and launch on the existing emulator**

Run:

```powershell
adb -s emulator-5556 install -r "build/app/outputs/flutter-apk/app-debug.apk"
adb -s emulator-5556 shell am force-stop com.example.note_secret_search
adb -s emulator-5556 shell monkey -p com.example.note_secret_search -c android.intent.category.LAUNCHER 1
```

Expected: `MainActivity` returns to foreground.

- [ ] **Step 3: Re-run the existing-PIN unlock path**

Use the same validated device path:

1. confirm `应用已锁定` page with `使用应用 PIN 解锁`;
2. open `PIN 解锁`;
3. enter the known PIN;
4. submit unlock;
5. inspect resulting UI/logs.

Expected: no blocking pop error symptom, no crash-like return failure, and the flow returns cleanly toward the unlocked state.

- [ ] **Step 4: If emulator behavior still fails, record only the remaining fix-caused delta**

If there is still a device-only issue, document exactly what remains after the navigator-first change rather than adding more routing fixes inside this slice.

---

## Self-Review Notes

- Spec coverage: approved A-scheme navigator-first fix, TDD-first regression reinforcement, focused verification, and emulator rerun are all represented.
- Placeholder scan: no broad routing refactor, no schema work, no unrelated auth changes.
- Type consistency: `AppLockGate` still opens `/unlock/pin` with `push<bool>()`; `PinUnlockPage` remains responsible for completing that return path.
