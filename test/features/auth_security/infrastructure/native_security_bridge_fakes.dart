part of 'native_security_bridge_test.dart';

class _CallbackNativeSecurityMethodInvoker
    implements NativeSecurityMethodInvoker {
  _CallbackNativeSecurityMethodInvoker(this.callback);

  final Future<Object?> Function(String method, Object? arguments) callback;

  @override
  Future<Object?> invokeMethod(String method, [Object? arguments]) {
    return callback(method, arguments);
  }
}
