import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_config.dart';

enum ExternalProviderConsentScope { standard, privateContext }

const int externalProviderPrivacyPolicyVersion = 1;
const int externalPrivateContextProjectionPolicyVersion = 1;

String normalizeExternalProviderEndpoint(String endpoint) {
  final uri = Uri.parse(endpoint.trim());
  final normalizedPath = uri.path.replaceFirst(RegExp(r'/+$'), '');
  return uri
      .replace(
        scheme: uri.scheme.toLowerCase(),
        host: uri.host.toLowerCase(),
        path: normalizedPath,
      )
      .toString();
}

String externalProviderConsentFingerprint(
  ExternalProviderConfig config, {
  ExternalProviderConsentScope scope = ExternalProviderConsentScope.standard,
}) {
  final canonicalIdentity = <String, Object>{
    'configId': config.id.trim(),
    'providerType': config.providerType.name,
    'endpoint': normalizeExternalProviderEndpoint(config.baseUrl),
    'model': config.modelName.trim(),
    'credentialDigest': sha256.convert(utf8.encode(config.apiKey)).toString(),
    'privacyPolicyVersion': externalProviderPrivacyPolicyVersion,
  };
  if (scope == ExternalProviderConsentScope.privateContext) {
    canonicalIdentity.addAll(<String, Object>{
      'allowSensitiveFields': config.allowSensitiveFields,
      'contextProjectionPolicyVersion':
          externalPrivateContextProjectionPolicyVersion,
    });
  }
  final canonical = jsonEncode(canonicalIdentity);
  return sha256.convert(utf8.encode(canonical)).toString();
}
