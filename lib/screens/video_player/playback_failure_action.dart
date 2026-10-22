import '../../mpv/models.dart';

/// What the player screen should do about one playback error.
enum PlaybackFailureAction {
  /// Server refused this account or connection with HTTP 403.
  playbackNotAllowedDialog,

  /// Server rejected the session with HTTP 500 — a bandwidth/transcoding limit.
  serverLimitDialog,

  /// Server could not read the file behind the item (HTTP 404).
  mediaUnreadableDialog,

  /// Server kept refusing the stream with HTTP 503 for the whole open phase.
  serverBusyDialog,

  /// Show the raw player error and leave the route.
  fatal,
}

/// Decides what [cause] plus the statuses seen on this open mean for playback.
///
/// Pure so the policy is testable without a player screen.
/// [fatalHttpStatuses] is the set of [fatalPlaybackHttpStatuses] entries the
/// player's log stream reported.
///
/// 403 is a refusal of this account or connection (#2510). It outranks every
/// other status latched on the same open — until the server lets this account
/// stream, what it says about the file or session is moot. 500 is a limit
/// rejection, which a retry does not clear. 404 means the file is unreadable.
/// 503 arrives only as the open-phase watchdog's cause tag (it never latches
/// into [fatalHttpStatuses]); by then the reconnect loop has had its chances.
///
/// An audio-output failure is checked first: the device stopped taking audio,
/// so a latched status would only re-open a stream into the same dead output.
///
/// [PlayerError.openTimedOut] and [PlayerError.streamInitFailed] name no
/// status and no device fault, so they take the default path like any other
/// failed open.
PlaybackFailureAction resolvePlaybackFailureAction({required String? cause, required Set<int> fatalHttpStatuses}) {
  if (cause == PlayerError.audioOutputFailed) return PlaybackFailureAction.fatal;

  if (fatalHttpStatuses.contains(403)) return PlaybackFailureAction.playbackNotAllowedDialog;

  if (cause == PlayerError.serverHttp500 || fatalHttpStatuses.contains(500)) {
    return PlaybackFailureAction.serverLimitDialog;
  }

  if (cause == PlayerError.serverHttp404 || fatalHttpStatuses.contains(404)) {
    return PlaybackFailureAction.mediaUnreadableDialog;
  }

  if (cause == PlayerError.serverHttp503) return PlaybackFailureAction.serverBusyDialog;

  return PlaybackFailureAction.fatal;
}
