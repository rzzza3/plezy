import 'dart:math';

/// 24-character random alphanumeric identifier used for transient session
/// handles (Plex `X-Plex-Session-Identifier`).
///
/// The format matches Plex's official client because the Plex transcoder
/// accepts that shape. Lifted out of `PlexClient` so other code paths don't
/// have to import the Plex client just to mint a session id.
String generateSessionIdentifier() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final rand = Random();
  return List.generate(24, (_) => chars[rand.nextInt(chars.length)]).join();
}
