abstract final class AppDestination {
  static const vault = '/vault';
  static const pinUnlock = '/unlock/pin';
  static const search = '/search';
  static const searchSettings = '/search/settings';
  static const notes = '/notes';
  static const aiChat = '/ai/chat';
  static const models = '/models';
  static const settings = '/settings';
  static const securitySettings = '/settings/security';
  static const pinSetup = '/settings/security/pin';
  static const externalProviders = '/settings/ai/providers';

  static String newSecret() => '$vault/secret/new';

  static String secretDetail(
    String id, {
    String? query,
    String? source,
    String? context,
  }) {
    return _withQuery(
      '$vault/secret/$id',
      query: query,
      source: source,
      context: context,
    );
  }

  static String editSecret(String id) => '$vault/secret/$id/edit';

  static String newNote() => '$notes/item/new';

  static String noteDetail(
    String id, {
    String? query,
    String? source,
    String? context,
  }) {
    return _withQuery(
      '$notes/item/$id',
      query: query,
      source: source,
      context: context,
    );
  }

  static String editNote(String id) => '$notes/item/$id/edit';

  static bool isProtected(Uri uri) {
    return uri.path == vault ||
        uri.path.startsWith('$vault/') ||
        uri.path == search ||
        uri.path.startsWith('$search/') ||
        uri.path == notes ||
        uri.path.startsWith('$notes/') ||
        uri.path == aiChat ||
        uri.path.startsWith('$aiChat/') ||
        uri.path == models ||
        uri.path.startsWith('$models/') ||
        uri.path == settings ||
        uri.path.startsWith('$settings/');
  }

  static String _withQuery(
    String path, {
    String? query,
    String? source,
    String? context,
  }) {
    final parameters = <String, String>{
      if (query != null) 'query': query,
      if (source != null) 'source': source,
      if (context != null) 'context': context,
    };
    return Uri(
      path: path,
      queryParameters: parameters.isEmpty ? null : parameters,
    ).toString();
  }
}
