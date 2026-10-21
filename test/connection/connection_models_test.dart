import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/connection/connection.dart';
import 'package:plezy/media/media_backend.dart';

/// Backend-agnostic [Connection] model tests pin config round-trips and derived
/// kind/backend mappings; registry persistence is covered separately.
void main() {
  group('PlexAccountConnection serialization', () {
    final base = PlexAccountConnection(
      id: 'plex.client-uuid',
      accountToken: 'token-xyz',
      clientIdentifier: 'client-uuid',
      accountLabel: 'edde',
      servers: const [],
      activeProfile: null,
      createdAt: DateTime.utc(2026, 1, 15),
      lastAuthenticatedAt: DateTime.utc(2026, 4, 25),
    );

    test('toConfigJson + fromConfigJson round-trip preserves identity fields', () {
      final json = base.toConfigJson();
      final restored = PlexAccountConnection.fromConfigJson(
        id: base.id,
        json: json,
        createdAt: base.createdAt,
        lastAuthenticatedAt: base.lastAuthenticatedAt,
      );
      expect(restored.id, base.id);
      expect(restored.accountToken, base.accountToken);
      expect(restored.clientIdentifier, base.clientIdentifier);
      expect(restored.accountLabel, base.accountLabel);
      expect(restored.servers, isEmpty);
      expect(restored.activeProfile, isNull);
      expect(restored.createdAt, base.createdAt);
      expect(restored.lastAuthenticatedAt, base.lastAuthenticatedAt);
    });

    test('fromConfigJson with empty payload uses safe defaults (no NPE)', () {
      final restored = PlexAccountConnection.fromConfigJson(
        id: 'orphan',
        json: const {},
        createdAt: DateTime.utc(2026),
      );
      expect(restored.id, 'orphan');
      expect(restored.accountToken, '');
      expect(restored.accountLabel, 'Plex');
      expect(restored.servers, isEmpty);
    });

    test('kind and backend match Plex', () {
      expect(base.kind, MediaBackend.plex);
      expect(base.backend, MediaBackend.plex);
    });
  });
}
