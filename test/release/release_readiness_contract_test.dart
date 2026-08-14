import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v0.2.1 version has one product owner', () {
    final pubspec = _read('pubspec.yaml');
    final versionMatch = RegExp(
      r'^version: ([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(versionMatch, isNotNull);
    expect(versionMatch!.group(1), '0.2.1');
    expect(versionMatch.group(2), '3');

    final policy = _json('config/release/release_artifact_policy.json');
    expect(policy['versionName'], versionMatch.group(1));
    expect(policy['versionCode'].toString(), versionMatch.group(2));
    expect(policy['tag'], 'v${versionMatch.group(1)}');

    final appGradle = _read('android/app/build.gradle.kts');
    expect(appGradle, isNot(contains('versionCode = 1')));
    expect(appGradle, isNot(contains('versionName = "0.1.0"')));
    expect(appGradle, contains('flutterVersionCode'));
    expect(appGradle, contains('flutterVersionName'));
  });

  test('release artifact policy pins provenance and packaging invariants', () {
    final policy = _json('config/release/release_artifact_policy.json');
    expect(policy['versionName'], '0.2.1');
    expect(policy['versionCode'], 3);
    expect(policy['tag'], 'v0.2.1');
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
      contains('assets/flutter_assets/assets/model_catalog/minicpm/'),
    );
  });

  test('Android release config keeps cleartext and debug flags closed', () {
    final manifest = _read('android/app/src/main/AndroidManifest.xml');
    expect(manifest, isNot(contains('usesCleartextTraffic="true"')));
    expect(manifest, contains('android:usesCleartextTraffic="false"'));
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
      expect(workflow, contains('Prepare Flutter Android version'));
      expect(workflow, contains('Invoke-AndroidArtifactAudit.ps1'));
      expect(workflow, isNot(contains('sign-release-candidate')));
      expect(workflow, isNot(contains('release-signing')));
      expect(workflow, isNot(contains('flutter build apk --debug')));
      expect(workflow, contains('retention-days: 7'));
      expect(workflow, contains('retention-days: 14'));
    },
  );

  test('quality workflow runs API 24 and API 34 artifact smoke jobs', () {
    final workflow = _read('.github/workflows/quality.yml');
    expect(workflow, contains('api24-smoke'));
    expect(workflow, contains('api-level: 24'));
    expect(workflow, contains('api34-smoke'));
    expect(workflow, contains('api-level: 34'));
    expect(workflow, contains('ReleaseReadinessSmokeInstrumentationTest'));
    expect(workflow, contains('app-debug-androidTest.apk'));
    expect(workflow, contains('zipalign'));
    expect(workflow, contains('apksigner'));
    expect(workflow, contains('build_tools_dir='));
    expect(workflow, contains('sort -V | tail -n 1'));
    expect(workflow, contains(r'test -n "$build_tools_dir"'));
    expect(
      workflow,
      isNot(
        contains(
          r'sdkmanager --sdk_root="$sdk_root" --install '
          "'build-tools;35.0.0'",
        ),
      ),
    );
    expect(
      workflow,
      contains(
        r'sdk_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}}"',
      ),
    );
    expect(workflow, contains(r'test -d "$sdk_root/build-tools"'));
    expect(
      workflow,
      contains(
        r'debug_keystore="${ANDROID_DEBUG_KEYSTORE:-$RUNNER_TEMP/nss-debug.keystore}"',
      ),
    );
    expect(workflow, contains('keytool -genkeypair -noprompt'));
    expect(workflow, contains(r'test -s "$debug_keystore"'));
    expect(workflow, contains(r'test -x "$zipalign"'));
    expect(workflow, contains(r'test -x "$apksigner"'));
    final smokeSetEu = RegExp(r'^\s+set -eu\s*$', multiLine: true);
    final bashPipefail = RegExp(r'^\s+set -euo pipefail\s*$', multiLine: true);
    expect(smokeSetEu.allMatches(workflow), hasLength(2));
    expect(bashPipefail.allMatches(workflow), hasLength(1));
  });

  test('release workflow keeps source and formal modes explicit', () {
    final workflow = _read('.github/workflows/release.yml');
    expect(workflow, contains('NSS_FORMAL_RELEASE_ENABLED'));
    expect(workflow, contains("vars.NSS_FORMAL_RELEASE_ENABLED != 'true'"));
    expect(workflow, contains("vars.NSS_FORMAL_RELEASE_ENABLED == 'true'"));
    expect(workflow, contains('release-signing'));
    expect(workflow, contains('release-publish'));
    expect(workflow, contains('NSS_RELEASE_KEYSTORE_BASE64'));
    expect(workflow, contains('verify --print-certs'));
    expect(workflow, contains('jarsigner -verify'));
    expect(workflow, contains('actions/attest-build-provenance'));
    expect(workflow, contains('gh release create'));
    expect(workflow, contains('contents: write'));
    expect(workflow, contains('app-release-signed.apk'));
    expect(workflow, contains('app-release-signed.aab'));
    expect(
      workflow,
      contains(r'sdk_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"'),
    );
    expect(workflow, contains(r'sdkmanager_path="$(command -v sdkmanager)"'));
    expect(workflow, contains(r'../../.."'));
    expect(
      workflow,
      contains(r'build_tools_dir=$(find "$sdk_root/build-tools"'),
    );
    expect(workflow, contains(r'test -n "$build_tools_dir"'));
    expect(workflow, contains('release-preflight'));
    expect(workflow, contains('release_tag:'));
    expect(workflow, contains('fetch-depth: 0'));
    expect(workflow, contains('git fetch --force --tags origin master'));
    expect(workflow, contains('git merge-base --is-ancestor'));
    expect(
      workflow,
      contains(
        'Release tag must point to the current origin/master merge commit.',
      ),
    );
    expect(
      workflow,
      contains(r'docs/release/$($env:RELEASE_TAG)-release-notes.md'),
    );
    expect(workflow, contains('release-ledger.md'));
    expect(workflow, contains('Release ledger still contains pending evidence'));
    expect(
      workflow,
      contains('NSS_RELEASE_CERT_SHA256 must be a configured'),
    );
    expect(workflow, contains('keytool -printcert -jarfile'));
    expect(workflow, contains('apk_cert'));
    expect(workflow, contains('aab_cert'));
    expect(workflow, isNot(contains('v0.2.0-release-notes.md')));
  });

  test('version preparation and artifact audit fail closed', () {
    final prepare = _read('scripts/quality/Prepare-FlutterAndroidVersion.ps1');
    expect(prepare, contains('build apk --config-only --no-pub'));
    expect(prepare, contains('flutter.versionName'));
    expect(prepare, contains('flutter.versionCode'));
    expect(prepare, contains('Gradle default 1.0/1'));

    final gradle = _read('android/app/build.gradle.kts');
    expect(gradle, contains('Properties'));
    expect(gradle, contains('local.properties is missing'));
    expect(gradle, contains('flutterVersionCode != 1'));
    expect(gradle, contains('flutterVersionName != "1.0"'));

    final audit = _read('scripts/quality/Invoke-AndroidArtifactAudit.ps1');
    expect(audit, contains("dump', 'badging'"));
    expect(audit, contains('VersionName'));
    expect(audit, contains('VersionCode'));
    expect(audit, contains('requiredTokenizerAssets'));
    expect(audit, contains('allowBackup'));
    expect(audit, contains('forbiddenReleaseNativeLibraries'));
  });

  test('Huawei closeout is serial-gated and backs up before installation', () {
    final script = _read('scripts/quality/Invoke-HuaweiReleaseCloseout.ps1');
    final common = _read('scripts/quality/HuaweiReleaseCloseout.Common.ps1');
    expect(script, contains('H8B4C19731000256'));
    expect(script, contains('HUAWEI'));
    expect(script, contains('SPN-AL00'));
    expect(script, isNot(contains("VersionName -eq '0.2.0'")));
    expect(script, isNot(contains('VersionCode -eq 2')));
    expect(script, contains('release_artifact_policy.json'));
    expect(script, contains('ExpectedVersionName'));
    expect(script, contains('ExpectedVersionCode'));
    expect(script, contains(r'$targetVersion = [version]$ExpectedVersionName'));
    expect(script, contains(r'$installedVersion = [version]$beforeMetadata.VersionName'));
    expect(script, contains(r'$isOlderOrSameTarget'));
    expect(script, contains('must not be newer'));
    expect(script, contains('MANUAL_UNLOCK_REQUIRED:huawei'));
    expect(script, contains(r'[DateTime]::UtcNow.AddMinutes(10)'));
    expect(script, contains("Invoke-Adb @('install', '-r'"));
    expect(
      script,
      contains('E:\\Archive\\Flutter\\.note_secret_search_device_backups'),
    );
     expect(script, contains('Backup-DeviceState'));
     expect(script, contains('finally'));
     expect(script, contains(r"'uninstall', $testPackageName"));
    expect(script, contains('Assert-BiometricHotfixFlow'));
    expect(script, contains('_UnmodifiableUint8ArrayView'));
    expect(script, contains('Test-DevicePathMissing'));
    expect(script, contains('Test-PackageMissing'));
    expect(script, contains('NSS_PRIVACY_SHIELD_ACTIVE'));
    expect(script, contains("'databases/'"));
    expect(script, contains("'shared_prefs/'"));
    expect(script, contains("'no_backup/security/'"));
    expect(script, contains('qwen2.5-0.5b-instruct-q4_k_m.gguf'));
    expect(script, contains('smollm2-360m-instruct-q8_0.gguf'));
    expect(script, contains(r'if ($testInstalled)'));
    expect(script, contains(r'throw $primaryError'));
    expect(common, contains(r"@('-s', $Serial)"));
    expect(common, contains('get-state'));
    expect(common, contains("'run-as'"));
    expect(common, contains("'sha256sum'"));
    expect(common, contains('RequireApplicationPid'));
     expect(script, contains('-RequireApplicationPid'));
    expect(common, contains(r'$ToolName.bat'));
    expect(common, contains('device-files-before.json'));
    expect(
      script.indexOf('Backup-DeviceState'),
      lessThan(script.indexOf("Invoke-Adb @('install', '-r'")),
    );
     expect(
       script.indexOf('install', script.indexOf("Invoke-Adb @('install', '-r'")),
       lessThan(script.indexOf(r"'uninstall', $testPackageName")),
     );
  });

  test('v0.2.1 release documents exist and preserve v0.2.0 history', () {
    for (final path in const [
      'CHANGELOG.md',
      'docs/release/v0.2.1-release-notes.md',
      'docs/release/v0.2.1-release-ledger.md',
      'docs/release/v0.2.0-release-notes.md',
      'docs/release/supported-devices.md',
      'docs/release/threat-model.md',
      'docs/release/known-limitations.md',
      'docs/release/v0.2.0-release-ledger.md',
    ]) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }

    final readme = _read('README.md');
    expect(readme, contains('0.2.1+3'));
    expect(readme, contains('Flutter 3.41.5'));
    expect(readme, contains('Release 仅允许 HTTPS'));
    expect(readme, contains('MiniCPM / 多模态未实现'));

    final ledger = _read('docs/release/v0.2.1-release-ledger.md');
    expect(ledger, contains('c3685894c116613bffe24b4ddb0cae797cebcd03'));
    expect(ledger, contains('SPN-AL00 / API 29'));
    expect(
      ledger,
      contains(
        '8e0ddd3aba851740eb787e345b4df1cff4d60603f289549c53a916aac99ddead',
      ),
    );
  });

  test(
    'local release gates consume artifacts without hard-coded Windows paths',
    () {
      final quality = _read('scripts/quality/Invoke-QualityChecks.ps1');
      expect(quality, contains('Resolve-GradleWrapper'));
      expect(quality, contains('-PackageOnce'));
      expect(quality, contains(r'Mandatory = $false'));
      expect(quality, isNot(contains('.\\gradlew.bat')));

      final aarGate = _read('scripts/quality/Invoke-LlmAarProvenanceGate.ps1');
      final aarCommon = _read('scripts/llm/LlmAarCommon.psm1');
      expect(aarGate, contains('SkipRebuild'));
      expect(aarGate, contains('Resolve-LlmNdkAuditTools'));
      expect(aarCommon, contains('Resolve-LlmAndroidSdkRoot'));
      expect(aarCommon, contains('Resolve-LlmNdkAuditTools'));
      expect(aarCommon, contains('linux-x86_64'));
      expect(aarCommon, contains('windows-x86_64'));
      expect(aarCommon, contains('LOCALAPPDATA'));

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
