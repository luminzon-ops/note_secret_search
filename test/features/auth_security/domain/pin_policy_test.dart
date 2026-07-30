import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/auth_security/domain/pin_policy.dart';

void main() {
  test('app PIN validation reports length before digit content', () {
    expect(AppPinPolicy.validate('12a'), PinValidationFailure.invalidLength);
    expect(
      AppPinPolicy.validate('123456789'),
      PinValidationFailure.invalidLength,
    );
  });

  test('app PIN validation accepts only 4-8 ASCII digits', () {
    expect(AppPinPolicy.validate('12a4'), PinValidationFailure.nonNumeric);
    expect(AppPinPolicy.validate('１２３４'), PinValidationFailure.nonNumeric);
    expect(AppPinPolicy.validate('1234'), isNull);
    expect(AppPinPolicy.validate('12345678'), isNull);
  });
}
