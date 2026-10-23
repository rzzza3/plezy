import 'package:flutter/material.dart';
import 'package:plezy/widgets/app_icon.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/focusable_wrapper.dart';
import '../../i18n/strings.g.dart';
import '../../media/media_backend.dart';
import '../../theme/mono_tokens.dart';
import '../../widgets/backend_badge.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../auth/silo_server_screen.dart';

/// Picker shown when the user taps "Add connection". Silo is the only
/// backend it offers.
///
/// Pops with `true` after the underlying flow succeeds so the parent list
/// refreshes; pops with `null` (the default) when the user backs out.
class AddConnectionScreen extends StatelessWidget {
  const AddConnectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final options = <_BackendOption>[
      _BackendOption(
        backend: MediaBackend.silo,
        title: t.silo.connectCard,
        subtitle: t.silo.connectCardSubtitle,
        builder: (_) => const SiloServerScreen(),
      ),
    ];
    final tokensRef = tokens(context);
    return FocusedScrollScaffold(
      title: Text(t.addServer.addConnectionTitle),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              for (var i = 0; i < options.length; i++) ...[
                if (i > 0) SizedBox(height: tokensRef.groupGap),
                _BackendCard(
                  borderRadius: groupItemRadii(context, i, options.length),
                  leading: BackendBadge(backend: options[i].backend, size: 28),
                  title: options[i].title,
                  subtitle: options[i].subtitle,
                  onTap: () async {
                    final added = await Navigator.push<bool>(context, MaterialPageRoute(builder: options[i].builder));
                    if (added == true && context.mounted) {
                      Navigator.of(context).pop(true);
                    }
                  },
                ),
              ],
            ]),
          ),
        ),
      ],
    );
  }
}

class _BackendOption {
  final MediaBackend backend;
  final String title;
  final String subtitle;
  final WidgetBuilder builder;

  const _BackendOption({required this.backend, required this.title, required this.subtitle, required this.builder});
}

class _BackendCard extends StatelessWidget {
  final BorderRadius borderRadius;
  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _BackendCard({
    required this.borderRadius,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The wrapper sits inside the Material so the focus fill paints above the
    // opaque surface color (an outside wrapper's fill would be invisible and
    // fall back to outline chrome).
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: FocusableWrapper(
        disableScale: true,
        useBackgroundFocus: true,
        borderRadii: borderRadius,
        descendantsAreFocusable: false,
        onSelect: onTap,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                const AppIcon(Symbols.chevron_right_rounded, fill: 1),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
