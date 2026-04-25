enum SecretDetailSearchHitTarget {
  none,
  title,
  username,
  website,
  tags,
  note,
}

enum NoteDetailSearchHitTarget {
  none,
  title,
  summary,
  content,
  tags,
}

String? resolveSecretDetailSearchFocusHint(String? searchContext) {
  switch (resolveSecretDetailSearchHitTarget(searchContext)) {
    case SecretDetailSearchHitTarget.title:
      return '标题，这是当前最直接的命中位置。';
    case SecretDetailSearchHitTarget.username:
      return '账号字段，这里最可能承载本次命中。';
    case SecretDetailSearchHitTarget.website:
      return '网址字段，确认站点是否与查询相关。';
    case SecretDetailSearchHitTarget.tags:
      return '标签字段，确认标签线索是否匹配。';
    case SecretDetailSearchHitTarget.note:
      return '备注字段，查看补充说明是否匹配查询意图。';
    case SecretDetailSearchHitTarget.none:
      return null;
  }
}

String? resolveSecretDetailHitExplanation(String? searchContext) {
  switch (resolveSecretDetailSearchHitTarget(searchContext)) {
    case SecretDetailSearchHitTarget.title:
      return '本次命中主要落在标题字段。';
    case SecretDetailSearchHitTarget.username:
      return '本次命中主要落在账号字段。';
    case SecretDetailSearchHitTarget.website:
      return '本次命中主要落在网址字段。';
    case SecretDetailSearchHitTarget.tags:
      return '本次命中主要落在标签字段。';
    case SecretDetailSearchHitTarget.note:
      return '本次命中主要落在备注字段。';
    case SecretDetailSearchHitTarget.none:
      return null;
  }
}

String? resolveNoteDetailSearchFocusHint(String? searchContext) {
  switch (resolveNoteDetailSearchHitTarget(searchContext)) {
    case NoteDetailSearchHitTarget.title:
      return '标题，这是当前最直接的命中位置。';
    case NoteDetailSearchHitTarget.summary:
      return '摘要，先确认概要是否对应本次查询。';
    case NoteDetailSearchHitTarget.content:
      return '正文内容，这里最可能包含本次命中上下文。';
    case NoteDetailSearchHitTarget.tags:
      return '标签字段，确认标签线索是否匹配。';
    case NoteDetailSearchHitTarget.none:
      return null;
  }
}

String? resolveNoteDetailHitExplanation(String? searchContext) {
  switch (resolveNoteDetailSearchHitTarget(searchContext)) {
    case NoteDetailSearchHitTarget.title:
      return '本次命中主要落在标题字段。';
    case NoteDetailSearchHitTarget.summary:
      return '本次命中主要落在摘要字段。';
    case NoteDetailSearchHitTarget.content:
      return '本次命中主要落在正文内容。';
    case NoteDetailSearchHitTarget.tags:
      return '本次命中主要落在标签字段。';
    case NoteDetailSearchHitTarget.none:
      return null;
  }
}

String? resolveSemanticFieldFocusHint(SemanticLikeField? field) {
  switch (field) {
    case SemanticLikeField.title:
      return '标题，这是当前最直接的命中位置。';
    case SemanticLikeField.username:
      return '账号字段，这里最可能承载本次命中。';
    case SemanticLikeField.website:
      return '网址字段，确认站点是否与查询相关。';
    case SemanticLikeField.summary:
      return '摘要，先确认概要是否对应本次查询。';
    case SemanticLikeField.tags:
      return '标签字段，确认标签线索是否匹配。';
    case SemanticLikeField.note:
      return '备注字段，查看补充说明是否匹配查询意图。';
    case SemanticLikeField.content:
      return '正文内容，这里最可能包含本次命中上下文。';
    case null:
      return null;
  }
}

enum SemanticLikeField {
  title,
  username,
  website,
  summary,
  tags,
  note,
  content,
}

SecretDetailSearchHitTarget resolveSecretDetailSearchHitTarget(String? searchContext) {
  final normalized = (searchContext ?? '').trim();
  if (normalized.startsWith('标题：')) {
    return SecretDetailSearchHitTarget.title;
  }
  if (normalized.startsWith('账号：')) {
    return SecretDetailSearchHitTarget.username;
  }
  if (normalized.startsWith('网址：')) {
    return SecretDetailSearchHitTarget.website;
  }
  if (normalized.startsWith('标签：')) {
    return SecretDetailSearchHitTarget.tags;
  }
  if (normalized.startsWith('附注：') || normalized.startsWith('备注：')) {
    return SecretDetailSearchHitTarget.note;
  }
  return SecretDetailSearchHitTarget.none;
}

NoteDetailSearchHitTarget resolveNoteDetailSearchHitTarget(String? searchContext) {
  final normalized = (searchContext ?? '').trim();
  if (normalized.startsWith('标题：')) {
    return NoteDetailSearchHitTarget.title;
  }
  if (normalized.startsWith('摘要：')) {
    return NoteDetailSearchHitTarget.summary;
  }
  if (normalized.startsWith('正文：')) {
    return NoteDetailSearchHitTarget.content;
  }
  if (normalized.startsWith('标签：')) {
    return NoteDetailSearchHitTarget.tags;
  }
  return NoteDetailSearchHitTarget.none;
}
