part of 'ai_chat_providers.dart';

final freeChatSemanticReadinessProvider =
    FutureProvider<SemanticSearchReadiness>((ref) {
      return guardSensitiveFuture<SemanticSearchReadiness>(
        ref,
        lockedValue: const SemanticSearchReadiness(
          ready: false,
          reason: '应用已锁定。',
        ),
        load: () => ref.watch(semanticSearchReadinessProvider.future),
      );
    });

final privateQaSemanticReadinessProvider =
    FutureProvider<SemanticSearchReadiness>((ref) {
      return guardSensitiveFuture<SemanticSearchReadiness>(
        ref,
        lockedValue: const SemanticSearchReadiness(
          ready: false,
          reason: '应用已锁定。',
        ),
        load: () => ref.watch(semanticSearchReadinessProvider.future),
      );
    });

final manualContextCandidatesProvider = FutureProvider<List<ChatContextItem>>((
  ref,
) {
  return guardSensitiveFuture<List<ChatContextItem>>(
    ref,
    lockedValue: const <ChatContextItem>[],
    load: () async {
      final secrets = await ref.watch(secretListProvider.future);
      final notes = await ref.watch(noteListProvider.future);
      return [
        ..._mapSecretsToContextItems(secrets),
        ..._mapNotesToContextItems(notes),
      ];
    },
  );
});
