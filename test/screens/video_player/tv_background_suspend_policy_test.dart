import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/screens/video_player/tv_background_suspend_policy.dart';

void main() {
  test('Android TV releases the player after the background grace period', () {
    expect(shouldSuspendPlayerForTvBackground(isAndroid: true, isTv: true, alreadySuspended: false), isTrue);
  });

  test('non-Android and non-TV players do not use the TV suspend flow', () {
    expect(shouldSuspendPlayerForTvBackground(isAndroid: false, isTv: true, alreadySuspended: false), isFalse);
    expect(shouldSuspendPlayerForTvBackground(isAndroid: true, isTv: false, alreadySuspended: false), isFalse);
  });

  test('an already suspended player is not scheduled again', () {
    expect(shouldSuspendPlayerForTvBackground(isAndroid: true, isTv: true, alreadySuspended: true), isFalse);
  });
}
