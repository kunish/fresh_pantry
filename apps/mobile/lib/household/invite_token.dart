import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

final _random = Random.secure();
final _tokenPattern = RegExp(r'^[A-Za-z0-9_-]{10,160}$');

String generateInviteToken() {
  const alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-';
  return List.generate(
    32,
    (_) => alphabet[_random.nextInt(alphabet.length)],
  ).join();
}

bool isInviteTokenShapeValid(String token) {
  return _tokenPattern.hasMatch(token);
}

String hashInviteToken(String token) {
  return sha256.convert(utf8.encode(token)).toString();
}
