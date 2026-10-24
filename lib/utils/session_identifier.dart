import 'dart:math';

/// 24-character random alphanumeric identifier used for transient session
/// handles, such as a playback session id.
String generateSessionIdentifier() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final rand = Random();
  return List.generate(24, (_) => chars[rand.nextInt(chars.length)]).join();
}
