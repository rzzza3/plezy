import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.g.dart';
import '../screens/profile/profile_switch_screen.dart';
import '../screens/profile/profile_teardown.dart';
import '../utils/dialogs.dart';
import '../widgets/app_icon.dart';
import '../widgets/app_menu.dart';
import 'active_profile_provider.dart';
import 'profile.dart';
import 'profile_avatar.dart';

/// The active-profile menu: the other profiles to switch to, then Profiles,
/// Settings and Logout. Values are resolved by [runProfileMenuAction].
List<AppMenuEntry<String>> profileMenuEntries(BuildContext context, ActiveProfileProvider activeProvider) {
  final theme = Theme.of(context);
  final activeProfile = activeProvider.active;
  final switchable = activeProvider.profiles.where((p) => p.id != activeProfile?.id).toList();

  return [
    for (final p in switchable)
      AppMenuItem<String>(
        value: 'profile:${p.id}',
        leading: ProfileAvatar(profile: p, size: 24, avatarUrl: activeProvider.avatarUrlFor(p.id)),
        label: p.displayName,
        trailing: p.isPinProtected
            ? AppIcon(Symbols.lock_rounded, fill: 1, size: 14, color: theme.colorScheme.onSurfaceVariant)
            : null,
      ),
    if (switchable.isNotEmpty) const AppMenuDivider(),
    AppMenuItem<String>(value: 'manage_profiles', icon: Symbols.group_rounded, label: t.profiles.sectionTitle),
    AppMenuItem<String>(value: 'settings', icon: Symbols.settings_rounded, label: t.common.settings),
    AppMenuItem<String>(value: 'logout', icon: Symbols.logout_rounded, label: t.common.logout),
  ];
}

Future<void> runProfileMenuAction(
  BuildContext context,
  String value, {
  required Future<void> Function(Profile profile) switchProfile,
  required VoidCallback openSettings,
}) async {
  switch (value) {
    case 'logout':
      unawaited(_confirmLogout(context));
    case 'manage_profiles':
      unawaited(
        Navigator.of(
          context,
          rootNavigator: true,
        ).push(MaterialPageRoute<void>(builder: (context) => const ProfileSwitchScreen())),
      );
    case 'settings':
      openSettings();
    default:
      if (!value.startsWith('profile:')) return;
      final id = value.substring('profile:'.length);
      final target = context.read<ActiveProfileProvider>().profiles.where((p) => p.id == id).firstOrNull;
      if (target != null) await switchProfile(target);
  }
}

Future<void> _confirmLogout(BuildContext context) async {
  final confirm = await showConfirmDialog(
    context,
    title: t.common.logout,
    message: t.messages.logoutConfirm,
    confirmText: t.common.logout,
    isDestructive: true,
  );
  if (confirm && context.mounted) {
    await logoutAllProfiles(context);
  }
}
