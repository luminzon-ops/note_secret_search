import 'package:note_secret_search/core/storage/database/sqlite_model_state_repository.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/model_catalog_trust.dart';

class SqliteModelCatalogAcceptanceStore implements ModelCatalogAcceptanceStore {
  SqliteModelCatalogAcceptanceStore({
    required SqliteModelStateRepository repository,
    int Function()? nowMilliseconds,
  }) : _repository = repository,
       _nowMilliseconds =
           nowMilliseconds ?? (() => DateTime.now().millisecondsSinceEpoch);

  final SqliteModelStateRepository _repository;
  final int Function() _nowMilliseconds;

  @override
  Future<ModelCatalogAcceptanceState?> read() async {
    final record = await _repository.loadCatalogState();
    if (record == null) {
      return null;
    }
    return ModelCatalogAcceptanceState(
      catalogVersion: record.acceptedVersion,
      payloadDigest: record.acceptedDigest,
      keyId: record.acceptedKeyId,
      minimumCatalogVersion: record.minimumAcceptedVersion,
      schemaVersion: record.acceptedSchemaVersion,
    );
  }

  @override
  Future<void> accept(ModelCatalogAcceptanceState state) {
    return _repository.saveCatalogState(
      ModelCatalogStateRecord(
        id: 'active',
        acceptedVersion: state.catalogVersion,
        acceptedDigest: state.payloadDigest,
        acceptedKeyId: state.keyId,
        acceptedSchemaVersion: state.schemaVersion,
        minimumAcceptedVersion: state.minimumCatalogVersion,
        updatedAt: _nowMilliseconds(),
      ),
    );
  }
}
