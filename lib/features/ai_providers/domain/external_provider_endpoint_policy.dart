import 'package:note_secret_search/features/ai_providers/domain/external_provider_config.dart';

enum ExternalProviderEndpointBuildMode { debug, release }

const defaultExternalProviderEndpointPolicy =
    bool.fromEnvironment('dart.vm.product')
    ? ExternalProviderEndpointPolicy.release()
    : ExternalProviderEndpointPolicy.debug();

class ExternalProviderEndpointPolicy {
  const ExternalProviderEndpointPolicy.release()
    : _mode = ExternalProviderEndpointBuildMode.release;

  const ExternalProviderEndpointPolicy.debug()
    : _mode = ExternalProviderEndpointBuildMode.debug;

  final ExternalProviderEndpointBuildMode _mode;

  String? validate(ExternalProviderConfig config) {
    return validateBaseUrl(config.baseUrl);
  }

  String? validateBaseUrl(String baseUrl) {
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) {
      return 'External provider endpoint must include a scheme and host.';
    }

    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'https') {
      return null;
    }
    if (scheme != 'http') {
      return 'External provider endpoint must use HTTPS.';
    }
    if (_mode == ExternalProviderEndpointBuildMode.release) {
      return 'Release builds require HTTPS external provider endpoints.';
    }
    if (_isLoopbackHost(uri.host)) {
      return null;
    }
    return 'Debug HTTP endpoints must use loopback hosts.';
  }

  bool _isLoopbackHost(String host) {
    final normalized = host.toLowerCase();
    return normalized == 'localhost' ||
        normalized == '127.0.0.1' ||
        normalized == '::1';
  }
}
