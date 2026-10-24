import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/connection/connection.dart';
import 'package:plezy/media/media_backend.dart';

/// Backend-agnostic [Connection] model tests pin config round-trips and derived
/// kind/backend mappings; registry persistence is covered separately.
void main() {
  group('SiloConnection serialization', () {
    final base = SiloConnection(
      origin: 'https://silo.example.com',
      serverId: 'server-1',
      serverName: 'Home',
      username: 'edde',
      accountId: 'account-1',
      createdAt: DateTime.utc(2026, 1, 15),
      lastAuthenticatedAt: DateTime.utc(2026, 4, 25),
    );

    test('toConfigJson + fromConfigJson round-trip preserves identity fields', () {
      final restored = SiloConnection.fromConfigJson(
        json: base.toConfigJson(),
        createdAt: base.createdAt,
        lastAuthenticatedAt: base.lastAuthenticatedAt,
      )!;
      expect(restored.id, base.id);
      expect(restored.origin, base.origin);
      expect(restored.serverId, base.serverId);
      expect(restored.serverName, base.serverName);
      expect(restored.username, base.username);
      expect(restored.accountId, base.accountId);
      expect(restored.createdAt, base.createdAt);
      expect(restored.lastAuthenticatedAt, base.lastAuthenticatedAt);
    });

    test('an unknown account id is not written', () {
      final json = base.copyWith(accountId: '').toConfigJson();
      expect(json, isNot(contains('accountId')));
      expect(SiloConnection.fromConfigJson(json: json, createdAt: base.createdAt)!.accountId, '');
    });

    test('fromConfigJson without origin or server id yields null', () {
      expect(SiloConnection.fromConfigJson(json: const {}, createdAt: DateTime.utc(2026)), isNull);
      expect(
        SiloConnection.fromConfigJson(
          json: const {'origin': 'https://silo.example.com'},
          createdAt: DateTime.utc(2026),
        ),
        isNull,
      );
    });

    test('copyWith keeps the server identity', () {
      final updated = base.copyWith(username: 'alice', lastAuthenticatedAt: DateTime.utc(2026, 5));
      expect(updated.id, 'silo:server-1');
      expect(updated.origin, base.origin);
      expect(updated.username, 'alice');
      expect(updated.accountId, 'account-1');
      expect(updated.createdAt, base.createdAt);
      expect(updated.lastAuthenticatedAt, DateTime.utc(2026, 5));
    });

    test('kind and backend match Silo', () {
      expect(base.kind, MediaBackend.silo);
      expect(base.backend, MediaBackend.silo);
    });
  });
}
