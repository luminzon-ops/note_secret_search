import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';

void main() {
  test('owns independent database and field key copies', () {
    final databaseSource = Uint8List.fromList(
      List<int>.generate(32, (index) => index),
    );
    final fieldSource = Uint8List.fromList(
      List<int>.generate(32, (index) => 255 - index),
    );
    final keys = DatabaseSessionKeys(
      databaseKey: databaseSource,
      fieldKey: fieldSource,
    );
    databaseSource.fillRange(0, databaseSource.length, 0);
    fieldSource.fillRange(0, fieldSource.length, 0);
    Uint8List? databaseLease;
    Uint8List? fieldLease;

    final databaseCopy = keys.withDatabaseKey((key) {
      databaseLease = key;
      return Uint8List.fromList(key);
    });
    final fieldCopy = keys.withFieldKey((key) {
      fieldLease = key;
      return Uint8List.fromList(key);
    });

    expect(databaseCopy, orderedEquals(List<int>.generate(32, (i) => i)));
    expect(fieldCopy, orderedEquals(List<int>.generate(32, (i) => 255 - i)));
    expect(databaseLease, everyElement(0));
    expect(fieldLease, everyElement(0));
  });

  test('clear is idempotent and rejects later key access', () {
    final keys = DatabaseSessionKeys(
      databaseKey: Uint8List(32),
      fieldKey: Uint8List(32),
    );

    keys.clear();
    keys.clear();

    expect(keys.isCleared, isTrue);
    expect(() => keys.withDatabaseKey((key) => key.length), throwsStateError);
    expect(() => keys.withFieldKey((key) => key.length), throwsStateError);
  });

  test('temporary key copy is cleared when the consumer throws', () {
    final keys = DatabaseSessionKeys(
      databaseKey: Uint8List.fromList(List<int>.filled(32, 7)),
      fieldKey: Uint8List.fromList(List<int>.filled(32, 9)),
    );
    Uint8List? lease;

    expect(
      () => keys.withFieldKey<void>((key) {
        lease = key;
        throw StateError('consumer failed');
      }),
      throwsStateError,
    );

    expect(lease, everyElement(0));
  });

  test('rejects asynchronous key consumers and clears their lease', () async {
    final keys = DatabaseSessionKeys(
      databaseKey: Uint8List.fromList(List<int>.filled(32, 7)),
      fieldKey: Uint8List.fromList(List<int>.filled(32, 9)),
    );
    final resume = Completer<void>();
    final observed = Completer<int>();
    Uint8List? lease;
    Object? error;

    try {
      keys.withFieldKey<Object?>((key) {
        lease = key;
        unawaited(() async {
          await resume.future;
          observed.complete(key.first);
        }());
        return observed.future;
      });
    } catch (caught) {
      error = caught;
    }

    expect(error, isA<StateError>());
    resume.complete();
    expect(await observed.future, 0);
    expect(lease, everyElement(0));
  });

  test('rejects Future<void> key consumers and clears their lease', () {
    final keys = DatabaseSessionKeys(
      databaseKey: Uint8List.fromList(List<int>.filled(32, 7)),
      fieldKey: Uint8List.fromList(List<int>.filled(32, 9)),
    );
    Uint8List? lease;

    expect(
      () => keys.withFieldKey<Future<void>>((key) {
        lease = key;
        return Future<void>.value();
      }),
      throwsStateError,
    );
    expect(lease, everyElement(0));
  });

  test('requires separate 32-byte keys', () {
    expect(
      () => DatabaseSessionKeys(
        databaseKey: Uint8List(31),
        fieldKey: Uint8List(32),
      ),
      throwsArgumentError,
    );
    expect(
      () => DatabaseSessionKeys(
        databaseKey: Uint8List(32),
        fieldKey: Uint8List(33),
      ),
      throwsArgumentError,
    );
  });

  test('store clears replaced and removed session keys', () {
    final first = DatabaseSessionKeys(
      databaseKey: Uint8List.fromList(List<int>.filled(32, 1)),
      fieldKey: Uint8List.fromList(List<int>.filled(32, 2)),
    );
    final second = DatabaseSessionKeys(
      databaseKey: Uint8List.fromList(List<int>.filled(32, 3)),
      fieldKey: Uint8List.fromList(List<int>.filled(32, 4)),
    );
    final store = DatabaseSessionKeyStore();

    store.replace(first);
    expect(store.requireCurrent(), same(first));

    store.replace(second);
    expect(first.isCleared, isTrue);
    expect(store.requireCurrent(), same(second));

    store.clear();
    store.clear();
    expect(second.isCleared, isTrue);
    expect(store.hasKeys, isFalse);
    expect(store.requireCurrent, throwsStateError);
  });
}
