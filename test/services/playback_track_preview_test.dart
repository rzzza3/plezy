import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import '../test_helpers/user_profile.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_server_user_profile.dart';
import 'package:plezy/media/media_source_info.dart';
import 'package:plezy/services/playback_track_preview.dart';
import 'package:plezy/services/plex_mappers.dart';
import 'package:plezy/services/plex_playback_mapper.dart';
import 'package:plezy/services/track_selection_service.dart';
import 'package:plezy/mpv/mpv.dart';

class _JapaneseAudioProfile implements MediaServerUserProfile {
  @override
  bool get autoSelectAudio => true;
  @override
  String? get defaultAudioLanguage => 'jpn';
  @override
  String? get defaultSubtitleLanguage => null;
  @override
  SubtitlePlaybackMode? get subtitleMode => null;
}

void main() {
  setUp(() {
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  // Plex `Part.Stream[]` rows as the server sends them (streamType 2=audio,
  // 3=subtitle); `selected` is the account's pick, `default` the container's.
  const english = {
    'id': 101,
    'streamType': 2,
    'index': 1,
    'codec': 'truehd',
    'language': 'English',
    'languageCode': 'eng',
    'channels': 8,
    'selected': true,
  };
  const japanese = {
    'id': 102,
    'streamType': 2,
    'index': 2,
    'codec': 'aac',
    'language': 'Japanese',
    'languageCode': 'jpn',
    'channels': 2,
  };
  const englishForced = {
    'id': 201,
    'streamType': 3,
    'index': 3,
    'codec': 'srt',
    'language': 'English',
    'languageCode': 'eng',
    'forced': true,
  };
  const englishFull = {
    'id': 202,
    'streamType': 3,
    'index': 4,
    'codec': 'ass',
    'language': 'English',
    'languageCode': 'eng',
    'title': 'Full',
  };

  const plexEpisode = MediaItem.plex(id: 'episode_1', kind: MediaKind.episode, title: 'Pilot');

  /// The `/library/metadata/{id}` row [plexMediaSourceInfoFromCacheJson]
  /// reads, as the item's own fetch caches it.
  MediaSourceInfo plexSource(List<Map<String, Object>> streams) => plexMediaSourceInfoFromCacheJson({
    'Media': [
      {
        'id': 1,
        'Part': [
          {'id': 11, 'Stream': streams},
        ],
      },
    ],
  })!;

  test('follows the server-selected audio and keeps subtitles off when Plex selected none', () {
    final preview = previewPlaybackTracks(plexEpisode, plexSource([english, japanese, englishForced, englishFull]))!;

    expect(preview.audio?.id, 101);
    expect(preview.audio?.label.joined, 'English · TrueHD · 7.1');
    expect(preview.subtitle, isNull);
    expect(preview.source.subtitleTracks.map((row) => row.id), [201, 202]);
  });

  test('a Plex-selected subtitle row is the prediction', () {
    final selectedFull = {...englishFull, 'selected': true};
    final preview = previewPlaybackTracks(plexEpisode, plexSource([english, japanese, englishForced, selectedFull]))!;

    expect(preview.subtitle?.id, 202);
  });

  test('the server pick outranks row order', () {
    final selectedJapanese = {...japanese, 'selected': true};
    final plainEnglish = {...english}..remove('selected');

    // Plex: the account's pick (Japanese) wins although English is first.
    expect(previewPlaybackTracks(plexEpisode, plexSource([plainEnglish, selectedJapanese]))!.audio?.id, 102);
    // No pick: the first row.
    expect(previewPlaybackTracks(plexEpisode, plexSource([plainEnglish, japanese]))!.audio?.id, 101);
  });

  test('profile language preference applies when the server selected nothing', () {
    final unselectedEnglish = {...english}..remove('selected');
    final preview = previewPlaybackTracks(
      plexEpisode,
      plexSource([unselectedEnglish, japanese]),
      profile: _JapaneseAudioProfile(),
    )!;

    expect(preview.audio?.id, 102);
  });

  test(
    'cached Plex audio fallback agrees with native defaults without promoting them over profile or manual picks',
    () {
      Map<String, dynamic> raw({bool containerDefault = true, bool serverSelected = false}) => {
        'Media': [
          {
            'id': 1,
            'Part': [
              {
                'id': 11,
                'key': '/library/parts/11/file.mkv',
                'Stream': [
                  {...english, 'selected': serverSelected},
                  {...japanese, 'default': containerDefault ? '1' : '0'},
                ],
              },
            ],
          },
        ],
      };
      const nativeEnglish = AudioTrack(id: '1', language: 'eng', codec: 'truehd', channels: 8);
      const nativeJapanese = AudioTrack(id: '2', language: 'jpn', codec: 'aac', channels: 2, isDefault: true);
      final cached = plexMediaSourceInfoFromCacheJson(raw())!;
      final opened = parsePlexVideoPlaybackDataFromJson(raw(), baseUrl: 'http://plex', token: null).mediaInfo!;
      final nativeSelection = TrackSelectionService(metadata: plexEpisode, plexMediaInfo: opened);
      expect(previewPlaybackTracks(plexEpisode, cached)!.audio?.languageCode, 'jpn');
      expect(nativeSelection.selectAudioTrack([nativeEnglish, nativeJapanese], null)!.track.language, 'jpn');
      expect(nativeSelection.selectAudioTrack([nativeEnglish, nativeJapanese], nativeEnglish)!.track.language, 'eng');
      expect(
        previewPlaybackTracks(
          plexEpisode,
          cached,
          profile: const TestUserProfile(playDefaultAudioTrack: true, preferredAudioLanguage: 'eng'),
        )!.audio?.languageCode,
        'eng',
      );
      expect(
        previewPlaybackTracks(plexEpisode, plexMediaSourceInfoFromCacheJson(raw(serverSelected: true))!)!.audio?.id,
        101,
      );
      expect(
        previewPlaybackTracks(plexEpisode, plexMediaSourceInfoFromCacheJson(raw(containerDefault: false))!)!.audio?.id,
        101,
      );
      // Manual/server selection rewrites must not erase the fallback when the
      // selection is subsequently cleared on the same source.
      final cleared = cached.copyWith(
        audioTracks: [for (final track in cached.audioTracks) track.withSelected(true).withSelected(false)],
      );
      expect(previewPlaybackTracks(plexEpisode, cleared)!.audio?.id, 102);
    },
  );

  test('a source without track rows yields no preview', () {
    // What the cache holds for a file the server has not probed.
    expect(previewPlaybackTracks(plexEpisode, plexSource(const [])), isNull);
  });
}
