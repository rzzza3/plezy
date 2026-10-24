/// Music streaming quality presets.
///
/// When a non-[original] preset is selected, track playback asks the active
/// backend for a bitrate-capped audio transcode (e.g.
/// `/music/:/transcode/universal` with `musicBitrate`). [original] bypasses transcoding and
/// direct-plays the source file. Deliberately separate from
/// [TranscodeQualityPreset] — its members are video-shaped
/// (resolution/videoQuality).
enum AudioQualityPreset {
  original(null),
  high(320),
  medium(192),
  low(128);

  const AudioQualityPreset(this.bitrateKbps);

  final int? bitrateKbps;

  bool get isOriginal => this == AudioQualityPreset.original;
}
