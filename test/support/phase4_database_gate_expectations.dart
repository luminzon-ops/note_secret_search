import 'phase3_database_gate_expectations.dart';

const phase4V6Tables = <String>{...phase3V5Tables, 'embedding_index_sets'};

final phase4V6Indexes =
    <String>{
      ...phase3V5Indexes,
      'uq_embedding_index_sets_source_model',
      'idx_embedding_index_sets_scope',
      'idx_embedding_chunks_set_field',
    }..removeAll(<String>{
      'uq_embedding_chunks_source_model_chunk',
      'idx_embedding_chunks_source',
      'idx_embedding_chunks_model',
    });

final phase4V6Triggers =
    <String>{
      ...phase3V5Triggers,
      'trg_embedding_index_sets_source_insert',
      'trg_embedding_index_sets_source_update',
      'trg_embedding_chunks_metadata_insert',
      'trg_embedding_chunks_metadata_update',
      'trg_secret_embedding_index_invalidate',
      'trg_secret_embedding_index_delete',
      'trg_note_embedding_index_invalidate',
      'trg_note_embedding_index_delete',
      'trg_item_tags_embedding_index_invalidate',
      'trg_item_tags_embedding_index_delete',
      'trg_item_tags_embedding_index_update',
      'trg_tags_embedding_index_invalidate',
      'trg_model_embedding_index_invalidate',
    }..removeAll(<String>{
      'trg_embedding_chunks_source_insert',
      'trg_embedding_chunks_source_update',
    });
