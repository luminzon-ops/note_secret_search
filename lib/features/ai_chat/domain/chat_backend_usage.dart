class ChatBackendUsage {
  const ChatBackendUsage({
    required this.actualBackend,
    required this.actualModel,
    this.providerFingerprint,
  });

  final String actualBackend;
  final String actualModel;
  final String? providerFingerprint;
}
