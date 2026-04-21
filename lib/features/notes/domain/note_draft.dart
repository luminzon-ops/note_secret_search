class NoteDraft {
  const NoteDraft({
    required this.title,
    required this.content,
    required this.summary,
    required this.tags,
    required this.categoryId,
    required this.favorite,
  });

  const NoteDraft.empty()
      : title = '',
        content = '',
        summary = '',
        tags = const <String>[],
        categoryId = null,
        favorite = false;

  final String title;
  final String content;
  final String summary;
  final List<String> tags;
  final String? categoryId;
  final bool favorite;
}
