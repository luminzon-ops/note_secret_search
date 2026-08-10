part 'model_catalog_entry_artifact.dart';
part 'model_catalog_entry_entry.dart';
part 'model_catalog_entry_parsing.dart';
part 'model_catalog_entry_source.dart';

class ModelCatalogFormatException implements Exception {
  const ModelCatalogFormatException(this.code);

  final String code;

  @override
  String toString() => code;
}
