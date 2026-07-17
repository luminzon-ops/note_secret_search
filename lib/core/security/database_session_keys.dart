import 'dart:async';
import 'dart:typed_data';

class DatabaseSessionKeys {
  DatabaseSessionKeys({
    required Uint8List databaseKey,
    required Uint8List fieldKey,
  }) : _databaseKey = _copyKey(databaseKey, 'databaseKey'),
       _fieldKey = _copyKey(fieldKey, 'fieldKey');

  final Uint8List _databaseKey;
  final Uint8List _fieldKey;
  bool _isCleared = false;

  bool get isCleared => _isCleared;

  T withDatabaseKey<T>(T Function(Uint8List key) consume) {
    return _withKey(_databaseKey, consume);
  }

  T withFieldKey<T>(T Function(Uint8List key) consume) {
    return _withKey(_fieldKey, consume);
  }

  void clear() {
    if (_isCleared) {
      return;
    }
    _databaseKey.fillRange(0, _databaseKey.length, 0);
    _fieldKey.fillRange(0, _fieldKey.length, 0);
    _isCleared = true;
  }

  T _withKey<T>(Uint8List key, T Function(Uint8List key) consume) {
    if (_isCleared) {
      throw StateError('Database session keys have been cleared.');
    }
    final lease = Uint8List.fromList(key);
    try {
      final result = consume(lease);
      if (result is Future<Object?>) {
        throw StateError('Database session key consumers must be synchronous.');
      }
      return result;
    } finally {
      lease.fillRange(0, lease.length, 0);
    }
  }

  static Uint8List _copyKey(Uint8List value, String name) {
    if (value.length != 32) {
      throw ArgumentError.value(value.length, name, 'Must contain 32 bytes.');
    }
    return Uint8List.fromList(value);
  }
}

class DatabaseSessionKeyStore {
  DatabaseSessionKeys? _current;

  bool get hasKeys {
    final current = _current;
    return current != null && !current.isCleared;
  }

  DatabaseSessionKeys requireCurrent() {
    final current = _current;
    if (current == null || current.isCleared) {
      throw StateError('Database session keys are unavailable.');
    }
    return current;
  }

  void replace(DatabaseSessionKeys keys) {
    if (keys.isCleared) {
      throw StateError('Cleared database session keys cannot be installed.');
    }
    final previous = _current;
    if (identical(previous, keys)) {
      return;
    }
    _current = keys;
    previous?.clear();
  }

  void clear() {
    final current = _current;
    _current = null;
    current?.clear();
  }
}
