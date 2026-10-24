import 'package:flutter/foundation.dart';

import '../connection/connection.dart';
import '../media/ids.dart';
import '../silo/silo_profiles.dart';
import '../utils/active_client_scope.dart';

/// A Silo profile — the user-facing identity in the app.
///
/// Silo owns the household, so profiles are never Plezy rows: the picker
/// reads them from the cached `/api/v2/profiles` list of each signed-in
/// server ([SiloHouseholdService]). The [id] is the client scope
/// `silo:<server_id>/<profile_id>`, which also owns downloads and
/// profile-scoped preferences.
@immutable
class Profile {
  const Profile({
    required this.serverId,
    required this.siloProfileId,
    required this.displayName,
    this.avatarThumbUrl,
    this.hasPin = false,
    this.isChild = false,
    this.isPrimary = false,
    this.sortOrder = 0,
    this.lastUsedAt,
  });

  /// [profile] as listed by the server at [serverId], in list position
  /// [sortOrder].
  factory Profile.fromSilo({
    required String serverId,
    required SiloProfile profile,
    required int sortOrder,
    DateTime? lastUsedAt,
  }) => Profile(
    serverId: serverId,
    siloProfileId: profile.id,
    displayName: profile.name,
    avatarThumbUrl: profile.avatarUrl,
    hasPin: profile.hasPin,
    isChild: profile.isChild,
    isPrimary: profile.isPrimary,
    sortOrder: sortOrder,
    lastUsedAt: lastUsedAt,
  );

  /// `server_id` of the Silo server that lists this profile.
  final String serverId;

  /// The profile's id on that server.
  final String siloProfileId;

  final String displayName;

  /// Absolute or server-relative avatar URL, or null for initials.
  final String? avatarThumbUrl;

  /// Entering the profile needs its PIN, checked by the server.
  final bool hasPin;
  final bool isChild;
  final bool isPrimary;

  /// Position in the server's list; the picker's tiebreak after [lastUsedAt].
  final int sortOrder;
  final DateTime? lastUsedAt;

  String get id => SiloProfileScopeId(serverId: ServerId(serverId), profileId: siloProfileId);

  /// The [SiloConnection] this profile signs in through.
  String get connectionId => SiloConnection.idFor(serverId);

  bool get isPinProtected => hasPin;

  Profile copyWith({String? displayName, String? avatarThumbUrl, bool? hasPin, DateTime? lastUsedAt}) => Profile(
    serverId: serverId,
    siloProfileId: siloProfileId,
    displayName: displayName ?? this.displayName,
    avatarThumbUrl: avatarThumbUrl ?? this.avatarThumbUrl,
    hasPin: hasPin ?? this.hasPin,
    isChild: isChild,
    isPrimary: isPrimary,
    sortOrder: sortOrder,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is Profile &&
      other.serverId == serverId &&
      other.siloProfileId == siloProfileId &&
      other.displayName == displayName &&
      other.avatarThumbUrl == avatarThumbUrl &&
      other.hasPin == hasPin &&
      other.isChild == isChild &&
      other.isPrimary == isPrimary &&
      other.sortOrder == sortOrder &&
      other.lastUsedAt == lastUsedAt;

  @override
  int get hashCode => Object.hash(
    serverId,
    siloProfileId,
    displayName,
    avatarThumbUrl,
    hasPin,
    isChild,
    isPrimary,
    sortOrder,
    lastUsedAt,
  );

  @override
  String toString() => 'Profile($id)';
}

/// THE builder for profile-scoped prefs keys: `user_{profileId}_{baseKey}`,
/// or the bare [baseKey] for the empty (signed-out/account-level) scope.
String profileScopedPrefsKey(String userUuid, String baseKey) =>
    userUuid.isEmpty ? baseKey : 'user_${userUuid}_$baseKey';
