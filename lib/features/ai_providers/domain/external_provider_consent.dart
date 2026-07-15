import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_config.dart';

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

String externalProviderConsentFingerprint(ExternalProviderConfig config) {
  final canonical = jsonEncode(<String, Object>{
    'providerType': config.providerType.name,
    'endpoint': normalizeExternalProviderEndpoint(config.baseUrl),
    'model': config.modelName.trim(),
    'allowSensitiveFields': config.allowSensitiveFields,
  });
  return sha256.convert(utf8.encode(canonical)).toString();
}
