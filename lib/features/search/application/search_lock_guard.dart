class SearchLockGuard {
  SearchLockGuard({required bool accessAllowed})
    : _accessAllowed = accessAllowed;

  bool _accessAllowed;
  int _epoch = 0;

  bool get accessAllowed => _accessAllowed;
  int get epoch => _epoch;

  void updateAccess(bool accessAllowed) {
    if (_accessAllowed && !accessAllowed) {
      _epoch += 1;
    }
    _accessAllowed = accessAllowed;
  }

  bool permits(int expectedEpoch) {
    return _accessAllowed && _epoch == expectedEpoch;
  }
}
