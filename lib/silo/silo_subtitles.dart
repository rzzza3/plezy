import 'silo_http.dart';
import 'silo_models.dart';
import 'silo_problem.dart';

/// One provider candidate from `POST /api/v2/subtitles/search`
/// (`S/network/apiv2/SubtitleReadsV2Api.kt:13-22`).
class SiloSubtitleCandidate {
  final String id;
  final String provider;
  final String language;
  final String releaseName;
  final String format;
  final double score;
  final int downloads;
  final bool hearingImpaired;

  const SiloSubtitleCandidate({
    required this.id,
    required this.provider,
    required this.language,
    required this.releaseName,
    required this.format,
    required this.score,
    this.downloads = 0,
    this.hearingImpaired = false,
  });

  /// Null when a required field is missing, so one bad row does not hide
  /// the rest.
  static SiloSubtitleCandidate? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final provider = json['provider'];
    final language = json['language'];
    final releaseName = json['release_name'];
    final format = json['format'];
    final score = json['score'];
    if (id == null || '$id'.isEmpty || provider is! String || language is! String) return null;
    if (releaseName is! String || format is! String || score is! num) return null;
    final downloads = json['downloads'];
    return SiloSubtitleCandidate(
      id: '$id',
      provider: provider,
      language: language,
      releaseName: releaseName,
      format: format,
      score: score.toDouble(),
      downloads: downloads is int ? downloads : 0,
      hearingImpaired: json['hearing_impaired'] == true,
    );
  }
}

class SiloSubtitleSearch {
  final List<SiloSubtitleCandidate> results;

  /// Provider notes, such as a provider that was skipped.
  final List<String> warnings;

  const SiloSubtitleSearch(this.results, this.warnings);
}

/// Provider search and download for one media file. A download stores the
/// subtitle on the server, so the playing session needs a `track_change`
/// replan before the new row is in its inventory
/// (`research/silo-playback.md` section 4, "External subtitles").
class SiloSubtitles {
  final SiloHttp http;

  const SiloSubtitles(this.http);

  /// `languages` are ISO 639-1 codes, at most 100
  /// (`S/network/apiv2/SubtitleReadsV2Api.kt:41-47`).
  Future<SiloSubtitleSearch> search(int mediaFileId, List<String> languages) async {
    if (mediaFileId <= 0 || languages.length > 100) throw const SiloDecodeException('subtitle search');
    final response = await http.send(
      SiloRequest.post('/api/v2/subtitles/search', body: {'media_file_id': '$mediaFileId', 'languages': languages}),
    );
    if (response.statusCode != 200) throw SiloApiException(response.statusCode, response.problem);
    final json = response.json();
    if (json is! Map || json['results'] is! List) throw const SiloDecodeException('results');
    final warnings = json['warnings'];
    return SiloSubtitleSearch([
      for (final row in json['results'] as List) ?SiloSubtitleCandidate.fromJson(row),
    ], warnings is List ? [for (final w in warnings) ?(w is String ? w : null)] : const []);
  }

  /// Stores [candidate] on the server and returns the stored row's id. Sent
  /// once: a retry could store it twice
  /// (`S/network/apiv2/SubtitleDownloadV2Api.kt:43-56`).
  Future<String> download(int mediaFileId, SiloSubtitleCandidate candidate) async {
    if (mediaFileId <= 0) throw const SiloDecodeException('media_file_id');
    final response = await http.send(
      SiloRequest.post(
        '/api/v2/subtitles/download',
        body: {
          'media_file_id': '$mediaFileId',
          'provider': candidate.provider,
          'subtitle_id': candidate.id,
          'language': candidate.language,
          'release_name': candidate.releaseName,
          'score': candidate.score,
          'hearing_impaired': candidate.hearingImpaired,
        },
        single: true,
      ),
    );
    if (response.statusCode != 200) throw SiloApiException(response.statusCode, response.problem);
    final json = response.json();
    final subtitle = json is Map ? json['subtitle'] : null;
    final id = subtitle is Map ? subtitle['id'] : null;
    final file = subtitle is Map ? subtitle['media_file_id'] : null;
    if (id == null || '$id'.isEmpty || '$file' != '$mediaFileId') throw const SiloDecodeException('subtitle');
    return '$id';
  }
}
