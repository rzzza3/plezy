import 'silo_http.dart';
import 'silo_problem.dart';

class SiloAccount {
  final String id;
  final String username;
  final String role;

  const SiloAccount({required this.id, required this.username, required this.role});

  bool get isAdmin => role.toLowerCase() == 'admin';

  static SiloAccount? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final username = json['username'];
    if (id == null || username is! String) return null;
    final role = json['role'];
    return SiloAccount(id: '$id', username: username, role: role is String ? role : '');
  }
}

class SiloProfile {
  final String id;
  final String name;
  final String? avatarUrl;
  final bool hasPin;
  final bool isChild;
  final bool isPrimary;

  const SiloProfile({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.hasPin = false,
    this.isChild = false,
    this.isPrimary = false,
  });

  static SiloProfile? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    if (id == null || '$id'.isEmpty || name is! String) return null;
    final avatarUrl = json['avatar_url'];
    return SiloProfile(
      id: '$id',
      name: name,
      avatarUrl: avatarUrl is String && avatarUrl.isNotEmpty ? avatarUrl : null,
      hasPin: json['has_pin'] == true,
      isChild: json['is_child'] == true,
      isPrimary: json['is_primary'] == true,
    );
  }
}

/// The account and its profiles, read under one identity.
class SiloHousehold {
  final SiloAccount account;
  final List<SiloProfile> profiles;

  const SiloHousehold(this.account, this.profiles);
}

sealed class SiloEnterResult {
  const SiloEnterResult();
}

final class SiloProfileEntered extends SiloEnterResult {
  const SiloProfileEntered();
}

/// The server said the PIN is wrong: `valid: false` or a blank token.
final class SiloPinRejected extends SiloEnterResult {
  const SiloPinRejected();
}

/// The identity moved while the PIN was checked, so the answer belongs to
/// nobody.
final class SiloEnterSuperseded extends SiloEnterResult {
  const SiloEnterSuperseded();
}

/// Profile reads and switches for the signed-in account. Follows
/// `TvProfileSelectionViewModel.kt:125-393`.
class SiloProfiles {
  final SiloHttp http;

  const SiloProfiles(this.http);

  /// Null when the identity changed during the reads, so the caller reloads
  /// instead of showing another account's profiles.
  Future<SiloHousehold?> load() async {
    final generation = http.session.generation;
    final me = await _getJson('/api/v2/account/me');
    final account = SiloAccount.fromJson(me);
    if (account == null) throw const SiloApiException(200);
    final list = await _getJson('/api/v2/profiles');
    final items = list is Map && list['items'] is List ? list['items'] as List : const [];
    if (http.session.generation != generation) return null;
    return SiloHousehold(account, [for (final item in items) ?SiloProfile.fromJson(item)]);
  }

  /// Enters [profile]. A PIN profile is checked with `verify-pin`, sent
  /// without profile headers, and entered only on `valid: true` with a
  /// non-blank token (`ProfileModels.kt:124-125`).
  Future<SiloEnterResult> enter(SiloProfile profile, {String? pin}) async {
    final generation = http.session.generation;
    String? token;
    if (profile.hasPin) {
      final response = await http.send(
        SiloRequest.post(
          '/api/v2/profiles/${Uri.encodeComponent(profile.id)}/verify-pin',
          body: {'pin': pin ?? ''},
          auth: SiloAuth.account,
        ),
      );
      if (response.statusCode != 200) throw SiloApiException(response.statusCode, response.problem);
      final json = response.json();
      final profileToken = json is Map ? json['profile_token'] : null;
      if (json is! Map || json['valid'] != true || profileToken is! String || profileToken.trim().isEmpty) {
        return const SiloPinRejected();
      }
      token = profileToken;
    }
    if (http.session.generation != generation) return const SiloEnterSuperseded();
    await http.session.selectProfile(profile.id, token);
    return const SiloProfileEntered();
  }

  Future<Object?> _getJson(String path) async {
    final response = await http.send(SiloRequest.get(path));
    if (response.statusCode != 200) throw SiloApiException(response.statusCode, response.problem);
    return response.json();
  }
}
