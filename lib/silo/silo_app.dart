import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/base_shared_preferences_service.dart';
import '../utils/app_logger.dart';
import '../utils/platform_detector.dart';
import 'silo_contract_gate.dart';
import 'silo_headers.dart';
import 'silo_http.dart';
import 'silo_server_probe.dart';
import 'silo_session.dart';
import 'silo_vault_store.dart';

/// Process-wide Silo state the screens and clients share: the device
/// headers, one session slot and contract gate per server, and the
/// cleartext approvals. A slot is loaded once so every holder sees the same
/// generation.
class SiloApp {
  SiloApp._();

  static const String _consentKey = 'silo_cleartext_consent';

  static Future<SiloHeaders>? _device;
  static final Map<String, Future<SiloSessionController>> _sessions = {};
  static final Map<String, SiloContractGate> _gates = {};
  static Future<SiloCleartextConsent>? _consent;

  static Future<SiloHeaders> device() => _device ??= _loadDevice();

  static Future<SiloSessionController> session(String serverId) =>
      _sessions[serverId] ??= SiloSessionController.load(VaultSiloSessionStore(serverId));

  static SiloContractGate gate(String origin) => _gates[origin] ??= SiloContractGate();

  static Future<SiloCleartextConsent> consent() => _consent ??= () async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    return SiloCleartextConsent(prefs.getStringList(_consentKey) ?? const []);
  }();

  /// False when [origin] cannot be named safely, so nothing was approved.
  static Future<bool> approveCleartext(String origin) async {
    final consent = await SiloApp.consent();
    if (!consent.approve(origin)) return false;
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setStringList(_consentKey, consent.digests.toList());
    return true;
  }

  static Future<SiloHttp> http({required Uri origin, required String serverId}) async {
    final consent = await SiloApp.consent();
    return SiloHttp(
      origin: origin,
      session: await session(serverId),
      device: await device(),
      gate: gate(siloOrigin(origin)),
      cleartextApproved: consent.isApproved,
    );
  }

  static Future<SiloHeaders> _loadDevice() async {
    String? manufacturer;
    String? model;
    String? version;
    try {
      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        manufacturer = info.manufacturer;
        model = info.model;
      }
      version = (await PackageInfo.fromPlatform()).version;
    } catch (error) {
      appLogger.d('Silo device metadata unavailable', error: error);
    }
    return SiloHeaders.load(
      store: const PrefsSiloDeviceIdStore(),
      isTv: PlatformDetector.isTV(),
      manufacturer: manufacturer,
      model: model,
      clientName: 'Plezy',
      version: version,
    );
  }
}
