class SecretDraft {
  const SecretDraft({
    required this.title,
    required this.username,
    required this.password,
    required this.websiteUrl,
    required this.note,
    required this.tags,
    required this.categoryId,
    required this.favorite,
  });

  const SecretDraft.empty()
      : title = '',
        username = '',
        password = '',
        websiteUrl = '',
        note = '',
        tags = const <String>[],
        categoryId = null,
        favorite = false;

  final String title;
  final String username;
  final String password;
  final String websiteUrl;
  final String note;
  final List<String> tags;
  final String? categoryId;
  final bool favorite;

  SecretDraft copyWith({
    String? title,
    String? username,
    String? password,
    String? websiteUrl,
    String? note,
    List<String>? tags,
    String? categoryId,
    bool? favorite,
    bool clearCategory = false,
  }) {
    return SecretDraft(
      title: title ?? this.title,
      username: username ?? this.username,
      password: password ?? this.password,
      websiteUrl: websiteUrl ?? this.websiteUrl,
      note: note ?? this.note,
      tags: tags ?? this.tags,
      categoryId: clearCategory ? null : categoryId ?? this.categoryId,
      favorite: favorite ?? this.favorite,
    );
  }
}
