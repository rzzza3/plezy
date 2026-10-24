/// Whether backgrounding may release the native video pipeline after its
/// grace period.
bool shouldSuspendPlayerForTvBackground({required bool isAndroid, required bool isTv, required bool alreadySuspended}) {
  return isAndroid && isTv && !alreadySuspended;
}
