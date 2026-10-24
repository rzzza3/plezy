import '../utils/language_codes.dart';
import 'media_server_user_profile.dart';

/// One account-scoped preference. Every key is stored on the media server or on
/// plex.tv, never on the device, and each backend supports a subset — see
/// [AccountPreferencesCapabilities].
enum AccountPreferenceKey {
  /// Preferred audio language. Plex `defaultAudioLanguage` (ISO 639-1).
  /// Applied by the server.
  preferredAudioLanguage(AccountPreferenceValueKind.languageCode),

  /// Auto-pick an audio track from the language preference instead of keeping
  /// the file's default. Plex `autoSelectAudio`. Applied by the server.
  autoSelectAudio(AccountPreferenceValueKind.boolean),

  /// Preferred subtitle language. Plex `defaultSubtitleLanguage`. Applied by
  /// the server.
  preferredSubtitleLanguage(AccountPreferenceValueKind.languageCode),

  /// When subtitles are auto-enabled. Plex `autoSelectSubtitle`. Applied by
  /// the server. Domains differ — see
  /// [AccountPreferencesCapabilities.subtitleModes].
  subtitleMode(AccountPreferenceValueKind.subtitleMode),

  /// Which item types show a watched badge. Plex `watchedIndicator`.
  /// Enforced by the client. Plex only.
  watchedIndicator(AccountPreferenceValueKind.watchedIndicator),

  /// Whose ratings and reviews to show. Plex `mediaReviewsVisibility`.
  /// Enforced by the client. Plex only.
  mediaReviewsVisibility(AccountPreferenceValueKind.mediaReviewsVisibility),

  /// SDH handling for subtitle *searches*. Plex
  /// `defaultSubtitleAccessibility`. Enforced by the client. Plex only.
  subtitleAccessibility(AccountPreferenceValueKind.subtitleAccessibility),

  /// Forced-subtitle handling for subtitle *searches*. Plex
  /// `defaultSubtitleForced`. Enforced by the client. Plex only.
  forcedSubtitles(AccountPreferenceValueKind.forcedSubtitles);

  const AccountPreferenceKey(this.valueKind);

  /// Shape of this key's value, so transports and UI can switch exhaustively.
  final AccountPreferenceValueKind valueKind;

  /// Whether the *server* applies this preference when answering queries, so a
  /// client must store it and otherwise stay out of the way. False means the
  /// client has to honour the value itself.
  bool get appliedByServer => switch (this) {
    AccountPreferenceKey.preferredAudioLanguage ||
    AccountPreferenceKey.autoSelectAudio ||
    AccountPreferenceKey.preferredSubtitleLanguage ||
    AccountPreferenceKey.subtitleMode => true,
    AccountPreferenceKey.watchedIndicator ||
    AccountPreferenceKey.mediaReviewsVisibility ||
    AccountPreferenceKey.subtitleAccessibility ||
    AccountPreferenceKey.forcedSubtitles => false,
  };
}

/// Value shape of an [AccountPreferenceKey].
enum AccountPreferenceValueKind {
  boolean,

  /// ISO 639-1 or a backend-specific language code, or null for "no preference".
  /// Mappers widen known ISO codes to whatever their backend stores.
  languageCode,
  subtitleMode,
  watchedIndicator,
  mediaReviewsVisibility,
  subtitleAccessibility,
  forcedSubtitles,
}

/// Which item types get a watched badge (Plex `watchedIndicator`).
enum WatchedIndicatorScope {
  none(0),
  moviesAndShows(1),
  movies(2),
  shows(3);

  const WatchedIndicatorScope(this.plexValue);
  final int plexValue;

  static WatchedIndicatorScope? fromPlexValue(int? value) =>
      value == null ? null : WatchedIndicatorScope.values.where((v) => v.plexValue == value).firstOrNull;
}

/// Whose ratings and reviews to surface (Plex `mediaReviewsVisibility`).
enum MediaReviewsVisibility {
  usersAndCritics(0),
  usersOnly(1),
  criticsOnly(2),
  nobody(3);

  const MediaReviewsVisibility(this.plexValue);
  final int plexValue;

  static MediaReviewsVisibility? fromPlexValue(int? value) =>
      value == null ? null : MediaReviewsVisibility.values.where((v) => v.plexValue == value).firstOrNull;
}

/// SDH preference for subtitle searches (Plex `defaultSubtitleAccessibility`).
enum SubtitleAccessibilityPreference {
  preferNonSdh(0),
  preferSdh(1),
  onlySdh(2),
  onlyNonSdh(3);

  const SubtitleAccessibilityPreference(this.plexValue);
  final int plexValue;

  static SubtitleAccessibilityPreference? fromPlexValue(int? value) =>
      value == null ? null : SubtitleAccessibilityPreference.values.where((v) => v.plexValue == value).firstOrNull;
}

/// Forced-subtitle preference for subtitle searches (Plex
/// `defaultSubtitleForced`).
enum ForcedSubtitlePreference {
  preferNonForced(0),
  preferForced(1),
  onlyForced(2),
  onlyNonForced(3);

  const ForcedSubtitlePreference(this.plexValue);
  final int plexValue;

  static ForcedSubtitlePreference? fromPlexValue(int? value) =>
      value == null ? null : ForcedSubtitlePreference.values.where((v) => v.plexValue == value).firstOrNull;
}

/// A read snapshot of one account's server-stored preferences.
///
/// Null means "unset or not supported by this backend"; consult
/// [AccountPreferencesCapabilities] to tell those apart. Language fields keep
/// the **server's own spelling** (Plex returns 639-1 `de`) because [MediaServerUserProfile] consumers match with
/// [LanguageCodes.getVariations]; the UI reads the `*Code1` accessors instead.
class AccountPreferences implements MediaServerUserProfile {
  const AccountPreferences({
    this.preferredAudioLanguage,
    this.playDefaultAudioTrack,
    this.preferredSubtitleLanguage,
    this.subtitlePlaybackMode,
    this.watchedIndicator,
    this.mediaReviewsVisibility,
    this.subtitleAccessibility,
    this.forcedSubtitles,
  });

  static const empty = AccountPreferences();

  final String? preferredAudioLanguage;
  final bool? playDefaultAudioTrack;
  final String? preferredSubtitleLanguage;
  final SubtitlePlaybackMode? subtitlePlaybackMode;
  final WatchedIndicatorScope? watchedIndicator;
  final MediaReviewsVisibility? mediaReviewsVisibility;
  final SubtitleAccessibilityPreference? subtitleAccessibility;
  final ForcedSubtitlePreference? forcedSubtitles;

  /// Preferred audio language narrowed to ISO 639-1 for pickers.
  String? get preferredAudioLanguageCode1 => _code1(preferredAudioLanguage);

  /// Preferred subtitle language narrowed to ISO 639-1 for pickers.
  String? get preferredSubtitleLanguageCode1 => _code1(preferredSubtitleLanguage);

  static String? _code1(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return LanguageCodes.getIso6391Code(raw) ?? raw;
  }

  /// Typed read of a single key, for generic UI rows.
  Object? operator [](AccountPreferenceKey key) => switch (key) {
    AccountPreferenceKey.preferredAudioLanguage => preferredAudioLanguageCode1,
    AccountPreferenceKey.autoSelectAudio => playDefaultAudioTrack,
    AccountPreferenceKey.preferredSubtitleLanguage => preferredSubtitleLanguageCode1,
    AccountPreferenceKey.subtitleMode => subtitlePlaybackMode,
    AccountPreferenceKey.watchedIndicator => watchedIndicator,
    AccountPreferenceKey.mediaReviewsVisibility => mediaReviewsVisibility,
    AccountPreferenceKey.subtitleAccessibility => subtitleAccessibility,
    AccountPreferenceKey.forcedSubtitles => forcedSubtitles,
  };

  // --- MediaServerUserProfile ------------------------------------------------
  // Implemented so the account cache can feed TrackSelectionService directly
  // instead of maintaining a second fetch path for the same fields.

  /// Defaults to true, matching Plex's own `autoSelectAudio` default when
  /// unset.
  @override
  bool get autoSelectAudio => playDefaultAudioTrack ?? true;

  @override
  String? get defaultAudioLanguage => preferredAudioLanguage;

  @override
  String? get defaultSubtitleLanguage => preferredSubtitleLanguage;

  @override
  SubtitlePlaybackMode? get subtitleMode => subtitlePlaybackMode;
}

/// A sparse set of changes to apply to one account.
///
/// Writes are patch-shaped because Plex Web sends only the changed keys as
/// query parameters.
class AccountPreferencesPatch {
  AccountPreferencesPatch(Map<AccountPreferenceKey, Object?> values)
    : _values = Map.unmodifiable({for (final entry in values.entries) entry.key: _checked(entry.key, entry.value)});

  AccountPreferencesPatch.of(AccountPreferenceKey key, Object? value) : this({key: value});

  final Map<AccountPreferenceKey, Object?> _values;

  Map<AccountPreferenceKey, Object?> get values => _values;

  Iterable<AccountPreferenceKey> get keys => _values.keys;

  bool get isEmpty => _values.isEmpty;

  bool get isNotEmpty => _values.isNotEmpty;

  bool contains(AccountPreferenceKey key) => _values.containsKey(key);

  /// Value for [key], or null when unset *or* explicitly cleared — callers
  /// gate on [contains] first.
  Object? operator [](AccountPreferenceKey key) => _values[key];

  bool? boolAt(AccountPreferenceKey key) => _values[key] as bool?;

  String? languageAt(AccountPreferenceKey key) => _values[key] as String?;

  AccountPreferencesPatch merge(AccountPreferencesPatch other) =>
      AccountPreferencesPatch({..._values, ...other._values});

  static Object? _checked(AccountPreferenceKey key, Object? value) {
    final ok = switch (key.valueKind) {
      AccountPreferenceValueKind.boolean => value is bool,
      AccountPreferenceValueKind.languageCode => value == null || value is String,
      AccountPreferenceValueKind.subtitleMode => value is SubtitlePlaybackMode,
      AccountPreferenceValueKind.watchedIndicator => value is WatchedIndicatorScope,
      AccountPreferenceValueKind.mediaReviewsVisibility => value is MediaReviewsVisibility,
      AccountPreferenceValueKind.subtitleAccessibility => value is SubtitleAccessibilityPreference,
      AccountPreferenceValueKind.forcedSubtitles => value is ForcedSubtitlePreference,
    };
    if (!ok) {
      throw ArgumentError('Invalid value for account preference ${key.name}');
    }
    return value;
  }

  @override
  String toString() => 'AccountPreferencesPatch(${_values.keys.map((k) => k.name).join(',')})';
}

/// What one backend actually stores, so the UI can hide rows it cannot write
/// and callers can distinguish "unset" from "unsupported".
class AccountPreferencesCapabilities {
  const AccountPreferencesCapabilities({required this.supportedKeys, required this.subtitleModes});

  /// plex.tv `/api/v2/user/profile`. `autoSelectSubtitle` has three states
  /// only: manual (`none`), with foreign audio (`smart`), always (`always`).
  static const plex = AccountPreferencesCapabilities(
    supportedKeys: {
      AccountPreferenceKey.preferredAudioLanguage,
      AccountPreferenceKey.autoSelectAudio,
      AccountPreferenceKey.preferredSubtitleLanguage,
      AccountPreferenceKey.subtitleMode,
      AccountPreferenceKey.watchedIndicator,
      AccountPreferenceKey.mediaReviewsVisibility,
      AccountPreferenceKey.subtitleAccessibility,
      AccountPreferenceKey.forcedSubtitles,
    },
    subtitleModes: {SubtitlePlaybackMode.none, SubtitlePlaybackMode.smart, SubtitlePlaybackMode.always},
  );

  static const unsupported = AccountPreferencesCapabilities(supportedKeys: {}, subtitleModes: {});

  final Set<AccountPreferenceKey> supportedKeys;

  /// Subtitle modes this backend can store. Empty when
  /// [AccountPreferenceKey.subtitleMode] is unsupported.
  final Set<SubtitlePlaybackMode> subtitleModes;

  bool supports(AccountPreferenceKey key) => supportedKeys.contains(key);

  /// Runtime validation shared by UI, command callers and transports.
  void validate(AccountPreferencesPatch patch) {
    for (final key in patch.keys) {
      if (!supports(key)) throw UnsupportedError('Unsupported account preference ${key.name}');
      if (key == AccountPreferenceKey.subtitleMode && !subtitleModes.contains(patch[key])) {
        throw ArgumentError('Unsupported subtitle mode for this account');
      }
    }
  }

  bool get isEmpty => supportedKeys.isEmpty;
}
