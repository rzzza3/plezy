import 'account_preferences.dart';
import 'account_ref.dart';

/// Read/write access to one account's server-stored preferences.
///
/// One instance per [AccountRef]; implementations own the wire mapping and are
/// created by the repository, never by UI. The current implementation
/// (`PlexAccountPreferencesSource`) throws the canonical [MediaServerException] hierarchy on failure — callers
/// must not flatten those into strings.
abstract class AccountPreferencesSource {
  /// What this backend can store. UI hides unsupported rows.
  AccountPreferencesCapabilities get capabilities;

  /// Fetch the authoritative current values.
  Future<AccountPreferences> read();

  /// Apply [patch] and return the account's state afterwards.
  ///
  /// Implementations must send only what [patch] names — Plex by putting
  /// exactly those keys in the query string. Writing a key the
  /// backend does not support is a programming error; the repository validates
  /// against [capabilities] first. Recheck [checkCurrent] before every commit.
  Future<AccountPreferences> write(AccountPreferencesPatch patch, {void Function()? checkCurrent});
}
