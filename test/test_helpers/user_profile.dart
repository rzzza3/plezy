import 'package:plezy/media/media_server_user_profile.dart';

/// Plain [MediaServerUserProfile] for track-selection tests.
class TestUserProfile implements MediaServerUserProfile {
  const TestUserProfile({
    this.preferredAudioLanguage,
    this.playDefaultAudioTrack,
    this.preferredSubtitleLanguage,
    this.subtitlePlaybackMode,
  });

  final String? preferredAudioLanguage;
  final bool? playDefaultAudioTrack;
  final String? preferredSubtitleLanguage;
  final SubtitlePlaybackMode? subtitlePlaybackMode;

  @override
  bool get autoSelectAudio => playDefaultAudioTrack ?? true;

  @override
  String? get defaultAudioLanguage => preferredAudioLanguage;

  @override
  String? get defaultSubtitleLanguage => preferredSubtitleLanguage;

  @override
  SubtitlePlaybackMode? get subtitleMode => subtitlePlaybackMode;
}
