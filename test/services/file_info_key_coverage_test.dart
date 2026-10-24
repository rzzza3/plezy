import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_file_info.dart';
import 'package:plezy/services/plex_playback_mapper.dart';

/// Guards the file-info sheet's promise that nothing the server reports is
/// silently dropped.
///
/// The fixtures below enumerate every key observed on the production request
/// shape — Plex `/library/metadata/{id}?includeChapters=1&includeMarkers=1`
/// `&checkFiles=1&includeStreams=1`. Each key must be accounted for exactly once:
/// carried onto the model, deliberately folded into another field, or listed
/// in an exclusion set with a reason. Adding a key to a fixture without
/// classifying it fails the suite.
void main() {
  group('Plex key coverage', () {
    test('every populated Media / Part / Stream key is classified', () {
      final info = parsePlexFileInfoFromJson(_plexMetadata)!;
      final version = info.versions.single;
      final part = version.parts.single;
      final video = part.streamsOfKind(MediaStreamKind.video).single;
      final audio = part.streamsOfKind(MediaStreamKind.audio).single;
      final subtitle = part.streamsOfKind(MediaStreamKind.subtitle).single;

      _expectClassified(
        observed: (_plexMetadata['Media']! as List).first as Map<String, dynamic>,
        carried: {
          'id': version.id,
          'title': version.title,
          'container': version.container,
          'bitrate': version.bitrateKbps,
          'duration': version.durationMs,
          'width': version.width,
          'height': version.height,
          'aspectRatio': version.aspectRatio,
          'videoResolution': version.videoResolutionLabel,
          'videoCodec': version.videoCodec,
          'videoProfile': version.videoProfile,
          'videoFrameRate': version.videoFrameRateLabel,
          'audioCodec': version.audioCodec,
          'audioProfile': version.audioProfile,
          'audioChannels': version.audioChannels,
          'optimizedForStreaming': version.optimizedForStreaming,
          'has64bitOffsets': version.has64bitOffsets,
          'proxyType': version.isOptimizedVersion,
          'target': version.optimizationTarget,
          'deletedAt': version.deletedAt,
          'displayOffset': version.displayOffsetPercent,
        },
        nested: const {'Part'},
        excluded: const {},
        label: 'Plex Media',
      );

      _expectClassified(
        observed: (_plexMedia['Part']! as List).first as Map<String, dynamic>,
        carried: {
          'id': part.id,
          'key': part.streamKey,
          'file': part.filePath,
          'size': part.fileSize,
          'container': part.container,
          'duration': part.durationMs,
          'indexes': part.indexes,
          'hasThumbnail': part.hasThumbnail,
          'has64bitOffsets': part.has64bitOffsets,
          'optimizedForStreaming': part.optimizedForStreaming,
          'packetLength': part.packetLength,
          'exists': part.exists,
          'accessible': part.accessible,
          'failureBIFResultCode': part.previewFailureCode,
          'failureBIFRetryCount': part.previewRetryCount,
        },
        nested: const {'Stream'},
        // Plex repeats the primary streams' profiles on the Part; the sheet
        // shows them once on the version and once per stream.
        excluded: const {'videoProfile', 'audioProfile'},
        label: 'Plex Part',
      );

      _expectClassified(
        observed: _plexVideoStream,
        carried: {
          'id': video.id,
          'index': video.index,
          'codec': video.codec,
          'codecID': video.codecTag,
          'profile': video.profile,
          'level': video.level,
          'title': video.title,
          'extendedDisplayTitle': video.displayTitle,
          'comment': video.comment,
          'language': video.language,
          'languageCode': video.languageCode,
          'bitrate': video.bitrateKbps,
          'default': video.isDefault,
          'selected': video.isSelected,
          'forced': video.isForced,
          'dub': video.isDub,
          'original': video.isOriginal,
          'width': video.width,
          'height': video.height,
          'codedWidth': video.codedWidth,
          'codedHeight': video.codedHeight,
          'frameRate': video.frameRate,
          'scanType': video.scanType,
          'bitDepth': video.bitDepth,
          'refFrames': video.refFrames,
          'colorSpace': video.colorSpace,
          'colorRange': video.colorRange,
          'colorPrimaries': video.colorPrimaries,
          'colorTrc': video.colorTransfer,
          'chromaSubsampling': video.chromaSubsampling,
          'chromaLocation': video.chromaLocation,
          'pixelAspectRatio': video.pixelAspectRatio,
          'anamorphic': video.isAnamorphic,
          'hasScalingMatrix': video.hasScalingMatrix,
          'streamIdentifier': video.streamIdentifier,
          'streamType': video.kind,
          'DOVIProfile': video.dolbyVision?.profile,
          'DOVILevel': video.dolbyVision?.level,
          'DOVIVersion': video.dolbyVision?.version,
          'DOVIBLCompatID': video.dolbyVision?.blCompatibilityId,
          'DOVIBLPresent': video.dolbyVision?.blPresent,
          'DOVIELPresent': video.dolbyVision?.elPresent,
          'DOVIRPUPresent': video.dolbyVision?.rpuPresent,
          'DOVIPresent': video.videoRange,
        },
        nested: const {},
        // `displayTitle` is the short form of `extendedDisplayTitle`, which is
        // what the stream card headline shows; `languageTag` is the same ISO
        // code as `languageCode`.
        excluded: const {'displayTitle', 'languageTag'},
        label: 'Plex video stream',
      );

      _expectClassified(
        observed: _plexAudioStream,
        carried: {
          'id': audio.id,
          'index': audio.index,
          'codec': audio.codec,
          'profile': audio.profile,
          'title': audio.title,
          'extendedDisplayTitle': audio.displayTitle,
          'comment': audio.comment,
          'language': audio.language,
          'languageCode': audio.languageCode,
          'bitrate': audio.bitrateKbps,
          'bitDepth': audio.bitDepth,
          'channels': audio.channels,
          'audioChannelLayout': audio.channelLayout,
          'samplingRate': audio.sampleRate,
          'default': audio.isDefault,
          'forced': audio.isForced,
          'selected': audio.isSelected,
          'dub': audio.isDub,
          'original': audio.isOriginal,
          'streamIdentifier': audio.streamIdentifier,
          'streamType': audio.kind,
        },
        nested: const {},
        excluded: const {'displayTitle', 'languageTag'},
        label: 'Plex audio stream',
      );

      _expectClassified(
        observed: _plexSubtitleStream,
        carried: {
          'id': subtitle.id,
          'index': subtitle.index,
          'codec': subtitle.codec,
          'title': subtitle.title,
          'extendedDisplayTitle': subtitle.displayTitle,
          'language': subtitle.language,
          'languageCode': subtitle.languageCode,
          'bitrate': subtitle.bitrateKbps,
          'default': subtitle.isDefault,
          'selected': subtitle.isSelected,
          'forced': subtitle.isForced,
          'hearingImpaired': subtitle.isHearingImpaired,
          'descriptions': subtitle.hasDescriptions,
          'headerCompression': subtitle.headerCompression,
          'dub': subtitle.isDub,
          'original': subtitle.isOriginal,
          'key': subtitle.externalKey,
          'format': subtitle.subtitleFormat,
          'providerTitle': subtitle.providerTitle,
          'score': subtitle.score,
          'sourceKey': subtitle.sourceKey,
          'transient': subtitle.isTransient,
          'streamIdentifier': subtitle.streamIdentifier,
          'streamType': subtitle.kind,
        },
        nested: const {},
        // `userID` is the Plex account that downloaded the subtitle — account
        // identity, not a property of the file.
        excluded: const {'displayTitle', 'languageTag', 'userID'},
        label: 'Plex subtitle stream',
      );
    });

    test('a sidecar subtitle key both marks the track external and is shown', () {
      final info = parsePlexFileInfoFromJson(_plexMetadata)!;
      final subtitle = info.versions.single.parts.single.streamsOfKind(MediaStreamKind.subtitle).single;
      expect(subtitle.isExternal, isTrue);
      expect(subtitle.externalKey, '/library/streams/47906');
    });

    test('checkFiles flags survive as file presence', () {
      final info = parsePlexFileInfoFromJson(_plexMetadata)!;
      final part = info.versions.single.parts.single;
      expect(part.exists, isTrue);
      expect(part.accessible, isFalse);
    });

    test('an optimized version is identified by proxyType 42', () {
      final version = parsePlexFileInfoFromJson(_plexMetadata)!.versions.single;
      expect(version.isOptimizedVersion, isTrue);
      expect(version.optimizationTarget, 'Mobile 720p');
      expect(version.deletedAt, DateTime.fromMillisecondsSinceEpoch(1780186199 * 1000));
    });

    test('a version without the optimized-version keys reports null, not false', () {
      final version = parsePlexFileInfoFromJson({
        'Media': [
          {
            'container': 'mkv',
            'Part': [
              {'file': '/media/plain.mkv'},
            ],
          },
        ],
      })!.versions.single;
      expect(version.isOptimizedVersion, isNull);
      expect(version.optimizationTarget, isNull);
      expect(version.deletedAt, isNull);
      expect(version.parts.single.exists, isNull);
      expect(version.parts.single.accessible, isNull);
    });
  });

  test('newly surfaced values keep their distinct semantics', () {
    final plexInfo = parsePlexFileInfoFromJson(_plexMetadata)!;
    expect(plexInfo.versions.single.displayOffsetPercent, 50);
    final plexSubtitle = plexInfo.versions.single.parts.single.streamsOfKind(MediaStreamKind.subtitle).single;
    expect(plexSubtitle.headerCompression, isTrue);
  });
}

/// Fails when [observed] carries a key that is neither projected onto the
/// model, recursed into, nor explicitly excluded — and when a key claimed as
/// carried did not actually survive the parse.
void _expectClassified({
  required Map<String, dynamic> observed,
  required Map<String, Object?> carried,
  required Set<String> nested,
  required Set<String> excluded,
  required String label,
}) {
  final classified = {...carried.keys, ...nested, ...excluded};
  final unclassified = observed.keys.where((key) => !classified.contains(key)).toList()..sort();
  expect(
    unclassified,
    isEmpty,
    reason:
        '$label exposes ${unclassified.join(', ')}. Map it onto MediaFileInfo, '
        'fold it into an existing field, or add it to the exclusion set with a reason.',
  );

  final dropped = carried.entries.where((entry) => observed[entry.key] != null && entry.value == null).toList();
  expect(
    dropped.map((entry) => entry.key).toList()..sort(),
    isEmpty,
    reason: '$label claims to carry ${dropped.map((e) => e.key).join(', ')} but the parsed value is null.',
  );
}

// --- Plex fixture: every key the production request shape returns ----------

const _plexVideoStream = <String, dynamic>{
  'id': 10032,
  'streamType': 1,
  'index': 0,
  'codec': 'hevc',
  'codecID': 'dvhe',
  'profile': 'main 10',
  'level': 153,
  'title': 'Presented By EMBER',
  'displayTitle': '4K DoVi',
  'extendedDisplayTitle': '4K DoVi/HDR10 (HEVC Main 10)',
  'language': 'English',
  'languageTag': 'en',
  'languageCode': 'eng',
  'bitrate': 50949,
  'bitDepth': 10,
  'width': 3840,
  'height': 2160,
  'codedWidth': 3840,
  'codedHeight': 2160,
  'frameRate': 23.976,
  'scanType': 'progressive',
  'refFrames': 1,
  'colorSpace': 'bt2020nc',
  'colorRange': 'tv',
  'colorPrimaries': 'bt2020',
  'colorTrc': 'smpte2084',
  'chromaSubsampling': '4:2:0',
  'chromaLocation': 'topleft',
  'pixelAspectRatio': '32:27',
  'anamorphic': true,
  'hasScalingMatrix': false,
  'comment': 'Presented By EMBER',
  'dub': false,
  'original': true,
  'forced': false,
  'streamIdentifier': '4117',
  'default': true,
  'selected': true,
  'DOVIPresent': true,
  'DOVIProfile': 8,
  'DOVILevel': 10,
  'DOVIVersion': '1.0',
  'DOVIBLCompatID': 1,
  'DOVIBLPresent': true,
  'DOVIELPresent': false,
  'DOVIRPUPresent': true,
};

const _plexAudioStream = <String, dynamic>{
  'id': 41919,
  'streamType': 2,
  'index': 1,
  'codec': 'eac3',
  'profile': 'dts',
  'title': 'English 5.1',
  'displayTitle': 'English (EAC3 5.1)',
  'extendedDisplayTitle': 'English (EAC3 5.1)',
  'comment': 'Dolby Atmos',
  'language': 'English',
  'languageTag': 'en',
  'languageCode': 'eng',
  'bitrate': 768,
  'bitDepth': 24,
  'channels': 6,
  'audioChannelLayout': '5.1',
  'samplingRate': 48000,
  'default': true,
  'forced': false,
  'selected': true,
  'dub': true,
  'original': true,
  'streamIdentifier': '3',
};

const _plexSubtitleStream = <String, dynamic>{
  'id': 49700,
  'streamType': 3,
  'index': 2,
  'codec': 'srt',
  'title': 'Full Subtitles [Cyan]',
  'displayTitle': 'English',
  'extendedDisplayTitle': 'Full subtitles (English SRT)',
  'language': 'English',
  'languageTag': 'en',
  'languageCode': 'eng',
  'bitrate': 2647,
  'default': true,
  'selected': true,
  'forced': false,
  'descriptions': false,
  'headerCompression': '1',
  'dub': false,
  'original': true,
  'hearingImpaired': true,
  'key': '/library/streams/47906',
  'format': 'srt',
  'providerTitle': 'OpenSubtitles',
  'score': 660,
  'sourceKey': '/library/streams/10522480',
  'transient': true,
  'streamIdentifier': '4',
  'userID': 625113360,
};

const _plexPart = <String, dynamic>{
  'id': 8930,
  'key': '/library/parts/9155/1773334775/file.mkv',
  'file': '/media/Movies/Example (2019)/Example (2019).mkv',
  'size': 28372183040,
  'container': 'mkv',
  'duration': 7139000,
  'indexes': 'sd',
  'hasThumbnail': true,
  'has64bitOffsets': false,
  'optimizedForStreaming': true,
  'packetLength': 188,
  'exists': true,
  'accessible': false,
  'failureBIFResultCode': 2,
  'failureBIFRetryCount': 3,
  'videoProfile': 'main 10',
  'audioProfile': 'dts',
  'Stream': [_plexVideoStream, _plexAudioStream, _plexSubtitleStream],
};

const _plexMedia = <String, dynamic>{
  'id': 10032,
  'title': 'Original',
  'container': 'mkv',
  'bitrate': 36400,
  'duration': 7139000,
  'width': 3840,
  'height': 2160,
  'aspectRatio': 2.4,
  'videoResolution': '4k',
  'videoCodec': 'hevc',
  'videoProfile': 'main 10',
  'videoFrameRate': '24p',
  'audioCodec': 'eac3',
  'audioProfile': 'dts',
  'audioChannels': 6,
  'optimizedForStreaming': true,
  'has64bitOffsets': false,
  'proxyType': 42,
  'target': 'Mobile 720p',
  'deletedAt': 1780186199,
  'displayOffset': 50,
  'Part': [_plexPart],
};

const _plexMetadata = <String, dynamic>{
  'Media': [_plexMedia],
};
