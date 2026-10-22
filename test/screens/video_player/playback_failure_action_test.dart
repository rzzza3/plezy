import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/mpv/models.dart';
import 'package:plezy/screens/video_player/playback_failure_action.dart';

PlaybackFailureAction resolve({String? cause, Set<int> statuses = const <int>{}}) {
  return resolvePlaybackFailureAction(cause: cause, fatalHttpStatuses: statuses);
}

void main() {
  group('HTTP 403', () {
    test('treats the refusal as terminal', () {
      // The server refused this account or connection (#2510); no retry,
      // quality change, or backend switch gets past it.
      expect(resolve(statuses: {403}), PlaybackFailureAction.playbackNotAllowedDialog);
    });

    test('outranks a 404 or 500 latched on the same open', () {
      // Until the server lets this account stream, what it says about the file
      // or the session is moot.
      expect(resolve(statuses: {403, 404}), PlaybackFailureAction.playbackNotAllowedDialog);
      expect(resolve(statuses: {403, 500}), PlaybackFailureAction.playbackNotAllowedDialog);
      expect(
        resolve(cause: PlayerError.serverHttp503, statuses: {403}),
        PlaybackFailureAction.playbackNotAllowedDialog,
      );
    });
  });

  group('HTTP 404', () {
    test('is terminal', () {
      // The file behind the item is unreadable server-side (#1750); no retry,
      // quality change, or backend switch recovers it.
      expect(resolve(statuses: {404}), PlaybackFailureAction.mediaUnreadableDialog);
      expect(resolve(cause: PlayerError.serverHttp404), PlaybackFailureAction.mediaUnreadableDialog);
    });
  });

  group('HTTP 500', () {
    test('is terminal', () {
      // A bandwidth/transcoding limit rejection is not something a retry
      // clears.
      expect(resolve(statuses: {500}), PlaybackFailureAction.serverLimitDialog);
      expect(resolve(cause: PlayerError.serverHttp500), PlaybackFailureAction.serverLimitDialog);
    });

    test('outranks a 404 latched on the same open', () {
      // The file may well exist; the server refused to serve it within limits.
      expect(resolve(statuses: {500, 404}), PlaybackFailureAction.serverLimitDialog);
    });
  });

  group('HTTP 503', () {
    test('surfaces the busy dialog', () {
      // The watchdog tags the cause only after the open phase answered 503 the
      // whole time; ffmpeg's reconnect loop has had its chances (#1830).
      expect(resolve(cause: PlayerError.serverHttp503), PlaybackFailureAction.serverBusyDialog);
    });

    test('yields to a 500 latched on the same open', () {
      expect(resolve(cause: PlayerError.serverHttp503, statuses: {500}), PlaybackFailureAction.serverLimitDialog);
    });
  });

  test('an audio-output failure is fatal regardless of latched statuses', () {
    // The device stopped taking audio. A latched status describes the
    // stream, which is fine — showing its dialog would misattribute the fault.
    expect(resolve(cause: PlayerError.audioOutputFailed, statuses: {403, 404, 500}), PlaybackFailureAction.fatal);
  });

  test('a failed open with no status is fatal', () {
    expect(resolve(cause: PlayerError.openTimedOut), PlaybackFailureAction.fatal);
    expect(resolve(cause: PlayerError.streamInitFailed), PlaybackFailureAction.fatal);
    expect(resolve(), PlaybackFailureAction.fatal);
  });
}
