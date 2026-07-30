import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/embedding_index_repository.dart';
import 'package:note_secret_search/features/search/domain/embedding_index_set.dart';
import 'package:note_secret_search/features/search/domain/float32_vector_codec.dart';
import 'package:note_secret_search/features/search/infrastructure/sqlite_embedding_repository.dart';

import '../../../support/sqlite_test_database.dart';

part 'sqlite_embedding_repository_fixture.dart';
part 'sqlite_embedding_repository_purge_cases.dart';
part 'sqlite_embedding_repository_replace_read_cases.dart';

void main() {
  _runSqliteEmbeddingReplaceReadCases();
  _runSqliteEmbeddingPurgeCases();
}
