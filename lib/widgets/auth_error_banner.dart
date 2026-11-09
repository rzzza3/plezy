import 'package:flutter/material.dart';
import '../media/ids.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.g.dart';
import '../providers/multi_server_provider.dart';
import 'app_icon.dart';

/// Top-of-app banner for servers that answered and refused this account
/// (HTTP 403, [MultiServerProvider.accessDeniedServers]). Distinct from
/// "server offline" — the server is reachable, so empty hubs need an
/// explanation. There is no CTA: a new sign-in gets the same refusal, and only
/// the server owner or the network the device is on can change it.
///
/// A rejected token (HTTP 401) never shows here: `ExpiredSessionSignOut`
/// signs that server out instead.
///
/// Collapses to `SizedBox.shrink()` when no visible server refuses.
class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final deniedEntries = context.select<MultiServerProvider, List<({ServerId serverId, String displayName})>>(
      (p) => p.accessDeniedServers,
    );
    if (deniedEntries.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              AppIcon(Symbols.block_rounded, fill: 1, color: scheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  deniedEntries.length == 1
                      ? t.connections.accessDeniedOne(name: deniedEntries.first.displayName)
                      : t.connections.accessDeniedMany(count: deniedEntries.length),
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onErrorContainer, fontWeight: .w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
