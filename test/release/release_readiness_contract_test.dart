import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v0.2.0 version has one product owner', () {
    expect(
      _read('pubspec.yaml'),
      contains(RegExp(r'^version: 0\.2\.0\+2$', multiLine: true)),
    );

    final appGradle = _read('android/app/build.gradle.kts');
    expect(appGradle, isNot(contains('versionCode = 1')));
    expect(appGradle, isNot(contains('versionName = "0.1.0"')));
    expect(appGradle, contains('flutterVersionCode'));
    expect(appGradle, contains('flutterVersionName'));
  });

  test('release artifact policy pins provenance and packaging invariants', () {
    final policy = _json('config/release/release_artifact_policy.json');
    expect(policy['versionName'], '0.2.0');
    expect(policy['versionCode'], 2);
    expect(policy['tag'], 'v0.2.0');
    expect(policy['flutter'], '3.41.5');
    expect(policy['dart'], '3.11.3');
    expect(policy['jdk'], '17');
    expect(policy['ndk'], '28.2.13676358');
    expect(
      policy['llamacppAarSha256'],
      '9583871b4179ae48ce3c57796fad21580167de4183ca6c28efdc2ed4724f9b41',
    );
    expect(policy['releaseMinifyEnabled'], isFalse);
    expect(policy['releaseShrinkResources'], isFalse);
    expect(policy['releaseObfuscationEnabled'], isFalse);
    expect(
      policy['forbiddenAssetPrefixes'],
      contains('flutter_assets/assets/model_catalog/minicpm/'),
    );
  });

  test('Android release config keeps cleartext and debug flags closed', () {
    final manifest = _read('android/app/src/main/AndroidManifest.xml');
    expect(manifest, isNot(contains('usesCleartextTraffic="true"')));
    expect(manifest, isNot(contains('android:debuggable="true"')));

    final appGradle = _read('android/app/build.gradle.kts');
    expect(appGradle, contains('isMinifyEnabled = false'));
    expect(appGradle, contains('isShrinkResources = false'));
  });

  test('release secrets and signing material are ignored', () {
    final gitignore = _read('.gitignore');
    for (final pattern in const ['*.jks', '*.keystore', 'key.properties']) {
      expect(gitignore, contains(pattern));
    }
  });

  test(
    'quality workflow packages Android artifacts once for all consumers',
    () {
      final workflow = _read('.github/workflows/quality.yml');
      expect(workflow, contains('workflow_call:'));
      expect(workflow, contains('permissions:'));
      expect(workflow, contains('contents: read'));
      expect(workflow, contains('package-once'));
      for (final task in const [
        ':app:assembleDebug',
        ':app:assembleDebugAndroidTest',
        ':app:assembleRelease',
        ':app:bundleRelease',
      ]) {
        expect(workflow, contains(task));
      }
      expect(workflow, isNot(contains('flutter build apk --debug')));
      expect(workflow, contains('retention-days: 7'));
      expect(workflow, contains('retention-days: 14'));
    },
  );

  test(
    'local release gates consume artifacts without hard-coded Windows paths',
    () {
      final quality = _read('scripts/quality/Invoke-QualityChecks.ps1');
      expect(quality, contains('Resolve-GradleWrapper'));
      expect(quality, contains('-PackageOnce'));
      expect(quality, isNot(contains('.\\gradlew.bat')));

      final aarGate = _read('scripts/quality/Invoke-LlmAarProvenanceGate.ps1');
      expect(aarGate, contains('SkipRebuild'));

      final deviceGate = _read(
        'scripts/quality/Invoke-EmbeddingRuntimeDeviceGate.ps1',
      );
      expect(deviceGate, contains('ExistingDebugApkPath'));
      expect(deviceGate, contains('ExpectedDebugApkSha256'));
    },
  );

  test('sensitive copy actions go through secure clipboard boundary', () {
    for (final path in const [
      'lib/features/notes/presentation/note_detail_page.dart',
      'lib/features/secrets/presentation/secret_detail_page.dart',
    ]) {
      final source = _read(path);
      expect(source, isNot(contains('Clipboard.setData')));
      expect(source, contains('secureClipboardControllerProvider'));
    }
  });
}

String _read(String path) => File(path).readAsStringSync();

Map<String, Object?> _json(String path) {
  return jsonDecode(_read(path)) as Map<String, Object?>;
}
