import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/app/router/lock_route_guard.dart';
import 'package:note_secret_search/core/security/lock_session.dart';
import 'package:note_secret_search/features/auth_security/domain/pin_state.dart';

void main() {
  group('LockRouteGuard', () {
    test('restores the full protected URI after unlock', () {
      final navigation = PostUnlockNavigation();
      final guard = LockRouteGuard(navigation: navigation);
      final protectedUri = Uri.parse(
        '/notes/item/note-1'
        '?query=bank%20account&source=semantic&context=note',
      );

      expect(
        guard.redirect(
          session: const LockSessionState.initial(),
          pinState: const PinState.initial(),
          uri: protectedUri,
        ),
        '/vault',
      );

      expect(
        guard.redirect(
          session: const LockSessionState(
            isUnlocked: true,
            pinEnabled: false,
            lastUnlockMethod: UnlockMethod.biometric,
            lockEpoch: 0,
          ),
          pinState: const PinState.initial(),
          uri: Uri.parse('/vault'),
        ),
        protectedUri.toString(),
      );
      expect(navigation.pendingDestination, isNull);
    });

    test('allows the PIN route only while usable PIN material exists', () {
      final navigation = PostUnlockNavigation();
      final guard = LockRouteGuard(navigation: navigation);
      const session = LockSessionState(
        isUnlocked: false,
        pinEnabled: true,
        lastUnlockMethod: null,
        lockEpoch: 0,
      );
      const pinState = PinState(
        enabled: true,
        hasPinMaterial: true,
        failedAttempts: 0,
        coolDownUntil: null,
        lastFailureAt: null,
      );

      expect(
        guard.redirect(
          session: session,
          pinState: pinState,
          uri: Uri.parse('/unlock/pin'),
        ),
        isNull,
      );
      expect(
        guard.redirect(
          session: session,
          pinState: const PinState.initial(),
          uri: Uri.parse('/unlock/pin'),
        ),
        '/vault',
      );
    });

    test('PIN replacement takes priority and then resumes the saved target', () {
      final navigation = PostUnlockNavigation();
      final guard = LockRouteGuard(navigation: navigation);
      final protectedUri = Uri.parse('/search?query=security%20key');

      guard.redirect(
        session: const LockSessionState.initial(),
        pinState: const PinState.initial(),
        uri: protectedUri,
      );
      navigation.requirePinReset();

      expect(
        guard.redirect(
          session: const LockSessionState(
            isUnlocked: true,
            pinEnabled: false,
            lastUnlockMethod: UnlockMethod.biometric,
            lockEpoch: 0,
          ),
          pinState: const PinState.initial(),
          uri: Uri.parse('/vault'),
        ),
        '/settings/security/pin',
      );

      navigation.completePinReset();

      expect(
        guard.redirect(
          session: const LockSessionState(
            isUnlocked: true,
            pinEnabled: true,
            lastUnlockMethod: UnlockMethod.biometric,
            lockEpoch: 0,
          ),
          pinState: const PinState(
            enabled: true,
            hasPinMaterial: true,
            failedAttempts: 0,
            coolDownUntil: null,
            lastFailureAt: null,
          ),
          uri: Uri.parse('/settings/security/pin'),
        ),
        protectedUri.toString(),
      );
      expect(navigation.pendingDestination, isNull);
    });
  });
}
