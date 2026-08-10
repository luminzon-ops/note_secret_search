abstract interface class ExternalProviderConsentStore {
  Future<bool> read(String key);

  Future<void> write(String key, bool value);

  Future<void> remove(String key);
}
