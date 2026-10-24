import 'package:uuid/uuid.dart';

/// Where the `X-Silo-Device-Id` lives. It is kept apart from the session so
/// signing out never changes it.
abstract interface class SiloDeviceIdStore {
  Future<String?> read();
  Future<void> write(String deviceId);
}

class MemorySiloDeviceIdStore implements SiloDeviceIdStore {
  String? _value;

  MemorySiloDeviceIdStore([this._value]);

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String deviceId) async => _value = deviceId;
}

/// The device identity Silo's server sees on every same-origin request.
class SiloHeaders {
  static const String deviceId = 'X-Silo-Device-Id';
  static const String deviceName = 'X-Silo-Device-Name';
  static const String devicePlatform = 'X-Silo-Device-Platform';
  static const String client = 'X-Silo-Client';
  static const String clientVersion = 'X-Silo-Client-Version';
  static const String clientBuild = 'X-Silo-Client-Build';
  static const String clientChannel = 'X-Silo-Client-Channel';
  static const String clientFamily = 'X-Silo-Client-Family';
  static const String profileId = 'X-Profile-Id';
  static const String profileToken = 'X-Profile-Token';
  static const String authorization = 'Authorization';

  final String id;
  final String name;
  final String platform;
  final String? clientName;
  final String? version;
  final String? build;
  final String? channel;
  final String? family;

  const SiloHeaders({
    required this.id,
    required this.name,
    required this.platform,
    this.clientName,
    this.version,
    this.build,
    this.channel,
    this.family,
  });

  /// Reads the persisted device id, creating it on first use.
  static Future<SiloHeaders> load({
    required SiloDeviceIdStore store,
    required bool isTv,
    required String? manufacturer,
    required String? model,
    String? clientName,
    String? version,
    String? build,
    String? channel,
    bool isTablet = false,
  }) async {
    var id = await store.read();
    if (id == null || id.isEmpty) {
      id = newSiloDeviceId();
      await store.write(id);
    }
    final parts = <String>[];
    for (final part in [manufacturer?.trim(), model?.trim()]) {
      if (part != null && part.isNotEmpty && !parts.contains(part)) parts.add(part);
    }
    return SiloHeaders(
      id: id,
      name: parts.isEmpty ? 'Android Device' : parts.join(' '),
      platform: siloDevicePlatform(isTv: isTv),
      clientName: clientName,
      version: version,
      build: build == '0' ? null : build,
      channel: channel,
      family: isTv ? 'tv' : (isTablet ? 'tablet' : 'mobile'),
    );
  }

  Map<String, String> toMap() => {
    deviceId: id,
    deviceName: name,
    devicePlatform: platform,
    if (clientName case final v? when v.trim().isNotEmpty) client: v,
    if (version case final v? when v.trim().isNotEmpty) clientVersion: v,
    if (build case final v? when v.trim().isNotEmpty) clientBuild: v,
    if (channel case final v? when v.trim().isNotEmpty) clientChannel: v,
    if (family case final v? when v.trim().isNotEmpty) clientFamily: v,
  };

  /// True for every header that must never leave the trusted origin.
  static bool isCredentialHeader(String name) {
    final lower = name.toLowerCase();
    return lower == 'authorization' ||
        lower == 'x-profile-id' ||
        lower == 'x-profile-token' ||
        lower.startsWith('x-silo-');
  }
}

String siloDevicePlatform({required bool isTv}) => isTv ? 'android-tv' : 'android';

String newSiloDeviceId() => const Uuid().v4();
