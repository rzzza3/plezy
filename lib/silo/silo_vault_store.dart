import '../services/base_shared_preferences_service.dart';
import '../services/credential_vault.dart';
import '../services/sensitive_prefs.dart';
import '../utils/serial_future_queue.dart';
import 'silo_headers.dart';
import 'silo_session.dart';

/// Persists the whole [SiloSessionState] as one vault-protected preference
/// value, so tokens, expiry, profile and generation land in a single write.
class VaultSiloSessionStore implements SiloSessionStore {
  static final SerialFutureQueue _persistence = SerialFutureQueue();

  const VaultSiloSessionStore();

  @override
  Future<SiloSessionState> read() => _persistence.run(() async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final raw = readTolerantString(prefs, siloSessionPref);
    if (raw == null || raw.isEmpty) return SiloSessionState.initial;
    final clear = await CredentialVault.reveal(raw);
    if (clear == null) return SiloSessionState.initial;
    return SiloSessionState.decode(clear);
  });

  @override
  Future<void> write(SiloSessionState state) => _persistence.run(() async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setString(siloSessionPref, await CredentialVault.protect(state.encode()));
  });
}

/// Keeps the device id in its own preference, outside the session value, so
/// sign-out and session loss leave it alone.
class PrefsSiloDeviceIdStore implements SiloDeviceIdStore {
  static const String key = 'silo_device_id';

  const PrefsSiloDeviceIdStore();

  @override
  Future<String?> read() async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    return readTolerantString(prefs, key);
  }

  @override
  Future<void> write(String deviceId) async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setString(key, deviceId);
  }
}
