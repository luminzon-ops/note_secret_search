import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/search/presentation/detail_search_hit_target.dart';

void main() {
  group('resolveSecretDetailSearchHitTarget', () {
    test('resolves secret title target', () {
      expect(
        resolveSecretDetailSearchHitTarget('标题：Bank Account'),
        SecretDetailSearchHitTarget.title,
      );
    });

    test('resolves secret username target', () {
      expect(
        resolveSecretDetailSearchHitTarget('账号：alice@example.com'),
        SecretDetailSearchHitTarget.username,
      );
    });

    test('resolves secret website target', () {
      expect(
        resolveSecretDetailSearchHitTarget('网址：bank.example.com'),
        SecretDetailSearchHitTarget.website,
      );
    });

    test('resolves secret tags target', () {
      expect(resolveSecretDetailSearchHitTarget('标签：finance'), SecretDetailSearchHitTarget.tags);
    });

    test('resolves secret note target for note aliases', () {
      expect(resolveSecretDetailSearchHitTarget('附注：bank note'), SecretDetailSearchHitTarget.note);
      expect(resolveSecretDetailSearchHitTarget('备注：bank note'), SecretDetailSearchHitTarget.note);
    });

    test('returns none for unknown prefix', () {
      expect(resolveSecretDetailSearchHitTarget('未知：value'), SecretDetailSearchHitTarget.none);
    });

    test('resolves secret focus hint from shared helper', () {
      expect(resolveSecretDetailSearchFocusHint('标题：Bank Account'), '标题，这是当前最直接的命中位置。');
      expect(resolveSecretDetailSearchFocusHint('账号：alice@example.com'), '账号字段，这里最可能承载本次命中。');
      expect(resolveSecretDetailSearchFocusHint('备注：bank note'), '备注字段，查看补充说明是否匹配查询意图。');
    });

    test('resolves secret hit explanation from shared helper', () {
      expect(resolveSecretDetailHitExplanation('标题：Bank Account'), '本次命中主要落在标题字段。');
      expect(resolveSecretDetailHitExplanation('账号：alice@example.com'), '本次命中主要落在账号字段。');
      expect(resolveSecretDetailHitExplanation('备注：bank note'), '本次命中主要落在备注字段。');
    });
  });

  group('resolveNoteDetailSearchHitTarget', () {
    test('resolves note title target', () {
      expect(resolveNoteDetailSearchHitTarget('标题：Recovery Note'), NoteDetailSearchHitTarget.title);
    });

    test('resolves note summary target', () {
      expect(resolveNoteDetailSearchHitTarget('摘要：恢复码备忘'), NoteDetailSearchHitTarget.summary);
    });

    test('resolves note content target', () {
      expect(resolveNoteDetailSearchHitTarget('正文：backup codes'), NoteDetailSearchHitTarget.content);
    });

    test('resolves note tags target', () {
      expect(resolveNoteDetailSearchHitTarget('标签：backup'), NoteDetailSearchHitTarget.tags);
    });

    test('returns none for unknown prefix', () {
      expect(resolveNoteDetailSearchHitTarget('未知：value'), NoteDetailSearchHitTarget.none);
    });

    test('resolves note focus hint from shared helper', () {
      expect(resolveNoteDetailSearchFocusHint('标题：Recovery Note'), '标题，这是当前最直接的命中位置。');
      expect(resolveNoteDetailSearchFocusHint('摘要：恢复码备忘'), '摘要，先确认概要是否对应本次查询。');
      expect(resolveNoteDetailSearchFocusHint('正文：backup codes'), '正文内容，这里最可能包含本次命中上下文。');
    });

    test('resolves note hit explanation from shared helper', () {
      expect(resolveNoteDetailHitExplanation('标题：Recovery Note'), '本次命中主要落在标题字段。');
      expect(resolveNoteDetailHitExplanation('摘要：恢复码备忘'), '本次命中主要落在摘要字段。');
      expect(resolveNoteDetailHitExplanation('正文：backup codes'), '本次命中主要落在正文内容。');
    });
  });
}
