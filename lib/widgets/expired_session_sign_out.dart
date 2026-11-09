import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/multi_server_provider.dart';
import '../screens/profile/profile_teardown.dart';

/// Signs this device out of any server that rejected its session (HTTP 401,
/// [MultiServerProvider.authErrorServerIds]) as soon as it is seen, instead
/// of leaving the app usable against a server that answers nothing. With no
/// server left the user lands on the sign-in screen.
///
/// Renders nothing.
class ExpiredSessionSignOut extends StatefulWidget {
  const ExpiredSessionSignOut({super.key});

  @override
  State<ExpiredSessionSignOut> createState() => _ExpiredSessionSignOutState();
}

class _ExpiredSessionSignOutState extends State<ExpiredSessionSignOut> {
  /// Servers already being signed out, so a repeat notification while the
  /// sign-out runs does not start a second one.
  final Set<String> _handled = {};

  @override
  Widget build(BuildContext context) {
    final expired = context.select<MultiServerProvider, List<String>>((p) => p.authErrorServerIds);
    final fresh = expired.whereNot(_handled.contains).toSet();
    if (fresh.isNotEmpty) {
      _handled.addAll(fresh);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(signOutExpiredSiloServers(context, fresh).whenComplete(() => _handled.removeAll(fresh)));
      });
    }
    return const SizedBox.shrink();
  }
}
