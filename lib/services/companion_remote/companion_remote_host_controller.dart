import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../connection/connection_registry.dart';
import '../../profiles/active_profile_provider.dart';
import '../../providers/companion_remote_provider.dart';
import '../../utils/app_logger.dart';

/// Primes companion-remote crypto with the active profile's Silo account,
/// returning whether crypto ended up ready.
///
/// Optional lifetime checks let an explicit settings mutation stop before a
/// stale async resolution commits crypto or starts a replacement session.
Future<bool> ensureCompanionRemoteCryptoFromContext(BuildContext context, {void Function()? checkCurrent}) async {
  checkCurrent?.call();
  return context.read<CompanionRemoteProvider>().ensureCryptoReady(
    connections: context.read<ConnectionRegistry>(),
    activeProfile: context.read<ActiveProfileProvider>(),
    checkCurrent: checkCurrent,
  );
}

Future<bool> startCompanionRemoteHost(BuildContext context, {void Function()? checkCurrent}) async {
  checkCurrent?.call();
  final companionRemote = context.read<CompanionRemoteProvider>();
  if (companionRemote.isHostServerRunning) return true;

  try {
    if (!await ensureCompanionRemoteCryptoFromContext(context, checkCurrent: checkCurrent)) return false;
    checkCurrent?.call();

    await companionRemote.startHostServer(checkCurrent: checkCurrent);
    checkCurrent?.call();
    return companionRemote.isHostServerRunning;
  } catch (e) {
    checkCurrent?.call();
    appLogger.e('CompanionRemote: Failed to start server', error: e);
    return false;
  }
}

Future<bool> applyCompanionRemoteServerSetting(
  BuildContext context,
  bool enabled, {
  void Function()? checkCurrent,
}) async {
  checkCurrent?.call();
  final companionRemote = context.read<CompanionRemoteProvider>();
  if (!enabled) {
    await companionRemote.stopHostServer(checkCurrent: checkCurrent);
    checkCurrent?.call();
    return !companionRemote.isHostServerRunning;
  }

  return startCompanionRemoteHost(context, checkCurrent: checkCurrent);
}
