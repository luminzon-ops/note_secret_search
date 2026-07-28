import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/core/security/core_security_providers.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/notes/domain/note_repository.dart';
import 'package:note_secret_search/features/search/application/content_mutation_search_coordinator.dart';
import 'package:note_secret_search/features/search/domain/search_index_settings.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';
import 'package:note_secret_search/features/secrets/domain/secret_repository.dart';
import 'package:note_secret_search/features/vault/application/vault_providers.dart';
import 'package:note_secret_search/features/vault/domain/vault.dart';
import 'package:note_secret_search/features/vault/domain/vault_repository.dart';

class ContentMutationSearchIndexRecorder {
  int indexPendingCalls = 0;
}

class CharacterizationCryptoService implements CryptoService {
  const CharacterizationCryptoService();

  @override
  String decryptNullable(
    List<int>? ciphertext, {
    required FieldCryptoContext context,
  }) {
    return ciphertext == null ? '' : String.fromCharCodes(ciphertext);
  }

  @override
  Uint8List? encryptNullable(
    String? plaintext, {
    required FieldCryptoContext context,
  }) {
    return plaintext == null ? null : Uint8List.fromList(plaintext.codeUnits);
  }
}

List<Override> contentMutationOverrides({
  required Vault? defaultVault,
  required ModelRegistryEntry? activeEmbeddingModel,
  required bool autoIndexEnabled,
  required ContentMutationSearchIndexRecorder indexRecorder,
}) {
  return <Override>[
    cryptoServiceProvider.overrideWith(
      (ref) => const CharacterizationCryptoService(),
    ),
    vaultRepositoryProvider.overrideWithValue(
      CharacterizationVaultRepository(defaultVault),
    ),
    contentMutationSearchSynchronizerProvider.overrideWith(
      (ref) => ContentMutationSearchCoordinator(
        loadActiveEmbeddingModel: () async => activeEmbeddingModel,
        loadIndexSettings: () async => SearchIndexSettings(
          autoIndexEnabled: autoIndexEnabled,
          maxChunkLength: 280,
        ),
        indexPending: () async {
          indexRecorder.indexPendingCalls += 1;
        },
        invalidateSearchProjections: () {},
      ),
    ),
  ];
}

class CharacterizationVaultRepository implements VaultRepository {
  const CharacterizationVaultRepository(this.defaultVault);

  final Vault? defaultVault;

  @override
  Future<Vault?> getDefaultVault() async => defaultVault;

  @override
  Future<List<Vault>> listAll() async {
    return defaultVault == null ? const <Vault>[] : <Vault>[defaultVault!];
  }

  @override
  Future<void> save(Vault vault) async {}
}

Vault characterizationVault() {
  final timestamp = DateTime(2026, 7, 26);
  return Vault(
    id: 'vault-1',
    name: 'Primary',
    description: null,
    isDefault: true,
    encryptionVersion: 1,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

const characterizationEmbeddingModel = ModelRegistryEntry(
  id: 'embedding-1',
  type: 'embedding',
  provider: 'local',
  name: 'Characterization embedding',
  version: null,
  sizeBytes: null,
  quantization: null,
  minRamMb: null,
  recommendedTier: null,
  localPath: null,
  checksum: null,
  enabled: false,
  installedAt: null,
  filePresent: false,
);

NoteItem characterizationNote() {
  final timestamp = DateTime(2026, 7, 26);
  return NoteItem(
    id: 'note-1',
    vaultId: 'vault-1',
    title: 'Existing note',
    contentCiphertext: 'Existing content'.codeUnits,
    summaryCacheCiphertext: 'Existing summary'.codeUnits,
    tags: const <String>['existing'],
    categoryId: null,
    favorite: false,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

SecretItem characterizationSecret() {
  final timestamp = DateTime(2026, 7, 26);
  return SecretItem(
    id: 'secret-1',
    vaultId: 'vault-1',
    title: 'Existing secret',
    usernameCiphertext: 'alice'.codeUnits,
    passwordCiphertext: 'password'.codeUnits,
    websiteUrlCiphertext: 'example.com'.codeUnits,
    noteCiphertext: 'Existing note'.codeUnits,
    tags: const <String>['existing'],
    categoryId: null,
    favorite: false,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

class RecordingNoteRepository implements NoteRepository {
  RecordingNoteRepository({this.item});

  final NoteItem? item;
  final List<NoteItem> savedItems = <NoteItem>[];
  final List<String> deletedIds = <String>[];

  @override
  Future<NoteItem?> getById(String id) async => item;

  @override
  Future<List<NoteItem>> listByVault(String vaultId) async {
    return item == null ? const <NoteItem>[] : <NoteItem>[item!];
  }

  @override
  Future<void> save(NoteItem item) async {
    savedItems.add(item);
  }

  @override
  Future<void> softDelete(String id) async {
    deletedIds.add(id);
  }
}

class RecordingSecretRepository implements SecretRepository {
  RecordingSecretRepository({this.item});

  final SecretItem? item;
  final List<SecretItem> savedItems = <SecretItem>[];
  final List<String> deletedIds = <String>[];

  @override
  Future<SecretItem?> getById(String id) async => item;

  @override
  Future<List<SecretItem>> listByVault(String vaultId) async {
    return item == null ? const <SecretItem>[] : <SecretItem>[item!];
  }

  @override
  Future<void> save(SecretItem item) async {
    savedItems.add(item);
  }

  @override
  Future<void> softDelete(String id) async {
    deletedIds.add(id);
  }
}
