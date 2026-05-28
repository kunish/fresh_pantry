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

String? inviteTokenFromInput(String input) {
  final trimmed = input.trim();
  if (isInviteTokenShapeValid(trimmed)) return trimmed;

  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;

  final token = _inviteTokenFromUri(uri);
  if (token == null || !isInviteTokenShapeValid(token)) return null;
  return token;
}

String? _inviteTokenFromUri(Uri uri) {
  if (!uri.hasScheme &&
      uri.pathSegments.length == 2 &&
      uri.pathSegments.first == 'invite') {
    return uri.pathSegments.last;
  }

  if ((uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.pathSegments.length == 2 &&
      uri.pathSegments.first == 'invite') {
    return uri.pathSegments.last;
  }

  if ((uri.scheme == 'com.kunish.freshpantry' || uri.scheme == 'freshpantry') &&
      uri.host == 'invite' &&
      uri.pathSegments.length == 1) {
    return uri.pathSegments.single;
  }

  return null;
}

String hashInviteToken(String token) {
  return sha256.convert(utf8.encode(token)).toString();
}
