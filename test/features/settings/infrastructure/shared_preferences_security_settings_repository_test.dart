import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/settings/domain/security_settings.dart';
import 'package:note_secret_search/features/settings/infrastructure/shared_preferences_security_settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('security settings never persist pin state or pin material', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final repository = SharedPreferencesSecuritySettingsRepository(
      preferences: preferences,
    );

    await repository.save(
      const SecuritySettings.defaults().copyWith(pinEnabled: true),
    );

    expect(preferences.getBool('security.pin_enabled'), isNull);
    expect(preferences.getString('security.pin_material'), isNull);
  });

  test('legacy pin preference cannot enable the native pin entry', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'security.pin_enabled': true,
      'security.pin_material': '2468',
    });
    final preferences = await SharedPreferences.getInstance();
    final repository = SharedPreferencesSecuritySettingsRepository(
      preferences: preferences,
    );

    final settings = await repository.load();

    expect(settings.pinEnabled, isFalse);
  });
}
