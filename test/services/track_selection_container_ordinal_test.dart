import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_source_info.dart';
import 'package:plezy/mpv/mpv.dart';
import 'package:plezy/services/track_selection_service.dart';

// The container-ordinal guards in `findMpvTrackForServerSubtitle` and
// `findServerTrackForMpvSubtitle` look like mirrors but are not: when the probe
// has no ordinal in the container list, the server->MPV direction still scores by
// metadata while the MPV->server direction refuses to match at all. These tests
// pin that difference so the two guards are not "symmetrised".

MediaSubtitleTrack _serverSub(int id, {int? index, String? languageCode}) =>
    MediaSubtitleTrack(id: id, index: index, languageCode: languageCode, selected: false, forced: false);

SubtitleTrack _containerSub(String id, {String? lang}) =>
    SubtitleTrack(id: id, language: lang, isExternal: true, isContainer: true);

void main() {
  group('container-ordinal guard asymmetry', () {
    test('server->MPV keeps metadata scoring when the server stream has no container ordinal', () {
      final probe = _serverSub(40, index: 0, languageCode: 'eng');
      final otherServerTracks = [_serverSub(41, index: 1, languageCode: 'eng')];
      final nativeTracks = [_containerSub('2_0', lang: 'eng')];

      expect(
        findMpvTrackForServerSubtitle(probe, nativeTracks, allServerTracks: otherServerTracks),
        nativeTracks.first,
      );
    });

    test('MPV->server refuses to match when the container track has no ordinal', () {
      final probe = _containerSub('2_0', lang: 'eng');
      final otherNativeTracks = [_containerSub('2_1', lang: 'eng')];
      final serverTracks = [_serverSub(40, index: 0, languageCode: 'eng')];

      expect(findServerTrackForMpvSubtitle(probe, serverTracks, allMpvTracks: otherNativeTracks), isNull);
    });
  });
}
