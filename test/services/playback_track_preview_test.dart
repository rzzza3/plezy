import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_server_user_profile.dart';
import 'package:plezy/media/media_source_info.dart';
import 'package:plezy/services/playback_track_preview.dart';

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

MediaAudioTrack _audio(
  int id, {
  required int index,
  required String codec,
  required String language,
  required String languageCode,
  required int channels,
  bool selected = false,
}) => MediaAudioTrack(
  id: id,
  index: index,
  codec: codec,
  language: language,
  languageCode: languageCode,
  channels: channels,
  selected: selected,
);

MediaSubtitleTrack _subtitle(
  int id, {
  required int index,
  required String codec,
  String? title,
  bool forced = false,
  bool selected = false,
}) => MediaSubtitleTrack(
  id: id,
  index: index,
  codec: codec,
  language: 'English',
  languageCode: 'eng',
  title: title,
  forced: forced,
  selected: selected,
);

MediaSourceInfo _source({List<MediaAudioTrack> audio = const [], List<MediaSubtitleTrack> subtitles = const []}) =>
    MediaSourceInfo(videoUrl: '', audioTracks: audio, subtitleTracks: subtitles, chapters: const []);

void main() {
  setUp(() {
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  // `selected` is the server's pick for the profile.
  MediaAudioTrack english({bool selected = true}) =>
      _audio(101, index: 1, codec: 'truehd', language: 'English', languageCode: 'eng', channels: 8, selected: selected);
  MediaAudioTrack japanese({bool selected = false}) =>
      _audio(102, index: 2, codec: 'aac', language: 'Japanese', languageCode: 'jpn', channels: 2, selected: selected);
  MediaSubtitleTrack englishForced() => _subtitle(201, index: 3, codec: 'srt', forced: true);
  MediaSubtitleTrack englishFull({bool selected = false}) =>
      _subtitle(202, index: 4, codec: 'ass', title: 'Full', selected: selected);

  const episode = MediaItem.silo(id: 'episode_1', kind: MediaKind.episode, title: 'Pilot');

  test('follows the server-selected audio and keeps subtitles off when the server selected none', () {
    final preview = previewPlaybackTracks(
      episode,
      _source(audio: [english(), japanese()], subtitles: [englishForced(), englishFull()]),
    )!;

    expect(preview.audio?.id, 101);
    expect(preview.audio?.label.joined, 'English · TrueHD · 7.1');
    expect(preview.subtitle, isNull);
    expect(preview.source.subtitleTracks.map((row) => row.id), [201, 202]);
  });

  test('a server-selected subtitle row is the prediction', () {
    final preview = previewPlaybackTracks(
      episode,
      _source(audio: [english(), japanese()], subtitles: [englishForced(), englishFull(selected: true)]),
    )!;

    expect(preview.subtitle?.id, 202);
  });

  test('the server pick outranks row order', () {
    // The account's pick (Japanese) wins although English is first.
    expect(
      previewPlaybackTracks(episode, _source(audio: [english(selected: false), japanese(selected: true)]))!.audio?.id,
      102,
    );
    // No pick: the first row.
    expect(previewPlaybackTracks(episode, _source(audio: [english(selected: false), japanese()]))!.audio?.id, 101);
  });

  test('profile language preference applies when the server selected nothing', () {
    final preview = previewPlaybackTracks(
      episode,
      _source(audio: [english(selected: false), japanese()]),
      profile: _JapaneseAudioProfile(),
    )!;

    expect(preview.audio?.id, 102);
  });

  test('a source without track rows yields no preview', () {
    // What the cache holds for a file the server has not probed.
    expect(previewPlaybackTracks(episode, _source()), isNull);
  });
}
