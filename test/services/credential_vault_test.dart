import 'dart:convert';

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/base_shared_preferences_service.dart';
import 'package:plezy/services/credential_vault.dart';
import 'package:plezy/services/sensitive_prefs.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import '../test_helpers/prefs.dart';

void main() {
  setUp(() {
    resetSharedPreferencesForTest();
    CredentialVault.resetKeyForTesting();
  });

  group('CredentialVault.reveal', () {
    test('round-trips a protected value', () async {
      final protected = await CredentialVault.protect('super-secret');
      expect(protected, startsWith('enc:v1:'));
      expect(await CredentialVault.reveal(protected), 'super-secret');
    });

    test('returns unprotected values unchanged', () async {
      expect(await CredentialVault.reveal('plaintext-token'), 'plaintext-token');
    });

    test('returns null instead of throwing on a tampered MAC', () async {
      final protected = await CredentialVault.protect('super-secret');
      final payload = jsonDecode(protected.substring('enc:v1:'.length)) as Map<String, dynamic>;
      payload['m'] = base64Encode(List<int>.filled(16, 0));
      final tampered = 'enc:v1:${jsonEncode(payload)}';

      expect(await CredentialVault.reveal(tampered), isNull);
    });

    test('returns null instead of throwing on a corrupt payload', () async {
      expect(await CredentialVault.reveal('enc:v1:not-json'), isNull);
      expect(await CredentialVault.reveal('enc:v1:{"n":"!!","c":"!!","m":"!!"}'), isNull);
      expect(await CredentialVault.reveal('enc:v1:{"n":"AAAA"}'), isNull);
    });

    test('returns null when the key diverged from the ciphertext', () async {
      final protected = await CredentialVault.protect('super-secret');

      // Simulate the key being lost/regenerated (cleared prefs, clobbered by
      // another isolate, restored backup) while the ciphertext survived.
      resetSharedPreferencesForTest();
      CredentialVault.resetKeyForTesting();

      expect(await CredentialVault.reveal(protected), isNull);
    });
  });

  group('CredentialVault.revealConnectionConfig', () {
    test('maps an undecryptable account token to the empty string without migrating', () async {
      final protected = await CredentialVault.protect('tok');
      resetSharedPreferencesForTest();
      CredentialVault.resetKeyForTesting();

      final result = await CredentialVault.revealConnectionConfig('plex', {
        'accountToken': protected,
        'servers': [
          {'accessToken': protected},
        ],
      });

      expect(result.config['accountToken'], '');
      expect((result.config['servers'] as List).single['accessToken'], '');
      expect(result.migrated, isFalse);
    });

    test('still reveals and flags plaintext tokens for migration', () async {
      final result = await CredentialVault.revealConnectionConfig('plex', {
        'accountToken': 'plain-tok',
        'servers': const [],
      });

      expect(result.config['accountToken'], 'plain-tok');
      expect(result.migrated, isTrue);
    });
  });

  group('CredentialVault key lookup', () {
    test('keeps other cached preferences readable while it reads the store', () async {
      final store = _GatedPreferences({'active_app_profile_id': 'local-profile'});
      SharedPreferencesAsyncPlatform.instance = store;
      BaseSharedPreferencesService.resetForTesting();
      final prefs = await BaseSharedPreferencesService.sharedCache();

      final reads = store.hold();
      final protecting = CredentialVault.protect('secret');
      await reads;

      // A profile switch reads the active id while the first reveal of the
      // session resolves the key.
      expect(prefs.getString('active_app_profile_id'), 'local-profile');

      store.release();
      expect(await CredentialVault.reveal(await protecting), 'secret');
    });

    test('adopts a key another isolate already stored', () async {
      final protected = await CredentialVault.protect('secret');
      final cached = await BaseSharedPreferencesService.sharedCache();
      final key = cached.getString(credentialVaultKeyPref)!;

      // A second isolate starts with a cache snapshot taken before the key
      // was written.
      SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
      BaseSharedPreferencesService.resetForTesting();
      await BaseSharedPreferencesService.sharedCache();
      CredentialVault.resetKeyForTesting();
      await SharedPreferencesAsyncPlatform.instance!.setString(
        credentialVaultKeyPref,
        key,
        const SharedPreferencesOptions(),
      );

      expect(await CredentialVault.reveal(protected), 'secret');
    });
  });
}

/// Holds store reads open until [release], so a test can look at the shared
/// cache while a read is in flight.
final class _GatedPreferences extends InMemorySharedPreferencesAsync {
  _GatedPreferences(super.data) : super.withData();

  Completer<void>? _gate;
  Completer<void>? _reached;

  /// Holds the next reads. Completes once one of them reaches the store.
  Future<void> hold() {
    _gate = Completer<void>();
    return (_reached = Completer<void>()).future;
  }

  void release() => _gate?.complete();

  @override
  Future<Map<String, Object>> getPreferences(
    GetPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async {
    final gate = _gate;
    if (gate != null) {
      if (!(_reached?.isCompleted ?? true)) _reached!.complete();
      await gate.future;
    }
    return super.getPreferences(parameters, options);
  }
}
