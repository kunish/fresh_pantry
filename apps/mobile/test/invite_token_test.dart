import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/household/invite_token.dart';

void main() {
  test('hashInviteToken returns stable sha256 hex', () {
    expect(
      hashInviteToken('abcDEF123_-'),
      '966149f22a6e83cf7cee9969192a095944b531cb0ebc15f4ded1e1cd71bf0368',
    );
  });

  test('isInviteTokenShapeValid rejects whitespace', () {
    expect(isInviteTokenShapeValid('abc DEF'), isFalse);
    expect(isInviteTokenShapeValid('abcDEF123_-'), isTrue);
  });

  test('inviteTokenFromInput accepts raw tokens and invite urls', () {
    expect(inviteTokenFromInput(' abcDEF123_- '), 'abcDEF123_-');
    expect(
      inviteTokenFromInput(
        'https://api.fresh-pantry.kunish.eu.org/invite/abcDEF123_-',
      ),
      'abcDEF123_-',
    );
    expect(
      inviteTokenFromInput('com.kunish.freshpantry://invite/abcDEF123_-'),
      'abcDEF123_-',
    );
    expect(inviteTokenFromInput('not a token'), isNull);
  });

  test('generateInviteToken returns url-safe tokens', () {
    final token = generateInviteToken();

    expect(token, hasLength(32));
    expect(isInviteTokenShapeValid(token), isTrue);
  });
}
