import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../connection/connection.dart';
import '../../focus/focusable_button.dart';
import '../../focus/focusable_wrapper.dart';
import '../../i18n/strings.g.dart';
import '../../profiles/active_profile_binder.dart';
import '../../profiles/active_profile_provider.dart';
import '../../profiles/profile.dart';
import '../../profiles/profile_connection.dart';
import '../../silo/silo_http.dart';
import '../../silo/silo_profiles.dart';
import '../../silo/silo_sign_in.dart';
import '../../utils/app_logger.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../settings/connection_persistence.dart';
import 'pin_entry_dialog.dart';
import 'profile_switch_screen.dart';

sealed class _PickerState {
  const _PickerState();
}

final class _Loading extends _PickerState {
  const _Loading();
}

final class _LoadFailed extends _PickerState {
  const _LoadFailed();
}

final class _Picking extends _PickerState {
  final SiloHousehold household;

  /// The profile being entered; the picker ignores taps meanwhile.
  final String? entering;
  final String? error;

  const _Picking(this.household, {this.entering, this.error});
}

/// Lists the account's Silo profiles and enters one
/// (`TvProfileSelectionViewModel.kt:125-393`). Entering binds the server to a
/// Plezy profile, with the Silo profile id on the join row, then pops with
/// `true`.
class SiloProfileScreen extends StatefulWidget {
  final SiloHttp silo;
  final SiloServerIdentity server;
  final Profile? targetProfile;

  const SiloProfileScreen({super.key, required this.silo, required this.server, this.targetProfile});

  @override
  State<SiloProfileScreen> createState() => _SiloProfileScreenState();
}

class _SiloProfileScreenState extends State<SiloProfileScreen> {
  late final SiloProfiles _profiles = SiloProfiles(widget.silo);
  _PickerState _state = const _Loading();
  bool _autoOpened = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _state = const _Loading());
    SiloHousehold? household;
    try {
      household = await _profiles.load() ?? await _profiles.load();
    } on Exception catch (error) {
      appLogger.w('Silo: profile list failed (${error.runtimeType})');
    }
    if (!mounted) return;
    if (household == null) return setState(() => _state = const _LoadFailed());
    appLogger.i('Silo: profile picker listed ${household.profiles.length} profiles');
    setState(() => _state = _Picking(household!));
    // A lone profile without a PIN opens by itself, once per sign-in
    // (`TvProfileSelectionViewModel.kt:175-189`).
    final only = household.profiles.length == 1 ? household.profiles.single : null;
    if (only != null && !only.hasPin && !_autoOpened) {
      _autoOpened = true;
      await _enter(only);
    }
  }

  Future<void> _enter(SiloProfile profile) async {
    final state = _state;
    if (state is! _Picking || state.entering != null) return;
    String? pin;
    if (profile.hasPin) {
      pin = await showPinEntryDialog(context, profile.name, errorMessage: state.error);
      if (pin == null || !mounted) return;
    }
    setState(() => _state = _Picking(state.household, entering: profile.id));
    final SiloEnterResult result;
    try {
      result = await _profiles.enter(profile, pin: pin);
    } on Exception catch (error) {
      appLogger.w('Silo: entering a profile failed (${error.runtimeType})');
      if (mounted) setState(() => _state = _Picking(state.household, error: t.silo.profilesFailed));
      return;
    }
    if (!mounted) return;
    switch (result) {
      case SiloPinRejected():
        appLogger.i('Silo: PIN rejected');
        setState(() => _state = _Picking(state.household, error: t.silo.wrongPin));
        unawaited(_enter(profile));
      case SiloEnterSuperseded():
        unawaited(_load());
      case SiloProfileEntered():
        appLogger.i('Silo: profile entered');
        if (await _bind(state.household, profile) && mounted) Navigator.of(context).pop(true);
    }
  }

  /// Persists the connection and the join row that names [profile], on the
  /// target profile, the active one, or a first-run local profile.
  Future<bool> _bind(SiloHousehold household, SiloProfile profile) async {
    final activeProfiles = context.read<ActiveProfileProvider>();
    final binder = context.read<ActiveProfileBinder>();
    await activeProfiles.initialize();
    if (!mounted) return false;
    var bindProfile = widget.targetProfile ?? activeProfiles.active;
    if (bindProfile == null && activeProfiles.profiles.isNotEmpty) {
      await Navigator.of(
        context,
        rootNavigator: true,
      ).push<bool>(MaterialPageRoute(builder: (_) => const ProfileSwitchScreen(requireSelection: true)));
      if (!mounted) return false;
      bindProfile = activeProfiles.active;
      if (bindProfile == null) return false;
    }
    final now = DateTime.now();
    final firstRunProfile = bindProfile == null
        ? Profile.local(
            id: 'local-${const Uuid().v4()}',
            displayName: profile.name,
            sortOrder: now.millisecondsSinceEpoch,
            createdAt: now,
          )
        : null;
    final owner = bindProfile ?? firstRunProfile!;
    final connection = SiloConnection(
      origin: widget.silo.origin.toString(),
      serverId: widget.server.serverId,
      serverName: widget.server.serverName,
      username: household.account.username,
      createdAt: now,
      lastAuthenticatedAt: now,
    );
    await persistAndBindConnection(
      context: context,
      connection: connection,
      bindToProfile: ProfileConnection(
        profileId: owner.id,
        connectionId: connection.id,
        userIdentifier: profile.id,
        tokenAcquiredAt: now,
      ),
      firstRunProfile: firstRunProfile,
    );
    if (owner.id == activeProfiles.activeId) await binder.rebindIfActive(owner.id);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    return FocusedScrollScaffold(
      title: Text(t.silo.profilesTitle),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: .fromLTRB(24, 16, 24, 24 + MediaQuery.paddingOf(context).bottom),
            child: Center(
              child: switch (state) {
                _Loading() => const CircularProgressIndicator(),
                _LoadFailed() => Column(
                  mainAxisSize: .min,
                  children: [
                    Text(t.silo.profilesFailed, style: Theme.of(context).textTheme.bodyLarge),
                    const SizedBox(height: 16),
                    FocusableButton(
                      autofocus: true,
                      onPressed: () => unawaited(_load()),
                      child: OutlinedButton(onPressed: () => unawaited(_load()), child: Text(t.common.retry)),
                    ),
                  ],
                ),
                _Picking(:final household, :final entering, :final error) => Column(
                  mainAxisSize: .min,
                  children: [
                    Wrap(
                      spacing: 24,
                      runSpacing: 24,
                      alignment: .center,
                      children: [
                        for (final (index, profile) in household.profiles.indexed)
                          _ProfileTile(
                            profile: profile,
                            autofocus: index == 0,
                            busy: entering == profile.id,
                            onSelect: () => unawaited(_enter(profile)),
                          ),
                      ],
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 24),
                      Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ],
                  ],
                ),
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final SiloProfile profile;
  final bool autofocus;
  final bool busy;
  final VoidCallback onSelect;

  const _ProfileTile({required this.profile, required this.autofocus, required this.busy, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = profile.name.isEmpty ? '?' : profile.name.characters.first.toUpperCase();
    final radius = BorderRadius.circular(16);
    return FocusableWrapper(
      autofocus: autofocus,
      borderRadii: radius,
      onSelect: onSelect,
      child: InkWell(
        onTap: onSelect,
        borderRadius: radius,
        child: SizedBox(
          width: 140,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: .min,
              children: [
                CircleAvatar(
                  radius: 44,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: busy
                      ? const CircularProgressIndicator()
                      : Text(initial, style: theme.textTheme.headlineMedium),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisSize: .min,
                  children: [
                    Flexible(
                      child: Text(profile.name, overflow: .ellipsis, style: theme.textTheme.titleMedium),
                    ),
                    if (profile.hasPin) ...[
                      const SizedBox(width: 4),
                      const AppIcon(Symbols.lock_rounded, fill: 1, size: 16),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
