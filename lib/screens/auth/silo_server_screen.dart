import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/focusable_button.dart';
import '../../focus/focusable_text_field.dart';
import '../../i18n/strings.g.dart';
import '../../mixins/controller_disposer_mixin.dart';
import '../../profiles/profile.dart';
import '../../silo/silo_app.dart';
import '../../silo/silo_http.dart';
import '../../silo/silo_server_probe.dart';
import '../../utils/app_logger.dart';
import '../../utils/dialogs.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../../widgets/loading_indicator_box.dart';
import 'silo_login_screen.dart';

sealed class _ServerStep {
  const _ServerStep();
}

final class _Editing extends _ServerStep {
  final String? error;

  const _Editing([this.error]);
}

final class _Probing extends _ServerStep {
  const _Probing();
}

/// Asks for the Silo server address and probes it
/// (`TvServerSetupViewModel.kt:178-337`). Pops with `true` once a profile on
/// the server is bound to a Plezy profile.
class SiloServerScreen extends StatefulWidget {
  final Profile? targetProfile;

  const SiloServerScreen({super.key, this.targetProfile});

  @override
  State<SiloServerScreen> createState() => _SiloServerScreenState();
}

class _SiloServerScreenState extends State<SiloServerScreen> with ControllerDisposerMixin {
  late final _address = createTextEditingController();
  final _addressFocus = FocusNode(debugLabel: 'SiloServer:addressFocus');
  final _connectFocus = FocusNode(debugLabel: 'SiloServer:connectFocus');
  _ServerStep _step = const _Editing();

  @override
  void dispose() {
    _addressFocus.dispose();
    _connectFocus.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_step is _Probing) return;
    setState(() => _step = const _Probing());
    appLogger.i('Silo: probing server address');
    final result = await probeSiloServer(_address.text, device: await SiloApp.device());
    if (!mounted) return;
    final error = switch (result) {
      SiloServerInvalidAddress() => t.silo.invalidAddress,
      SiloServerUnreachable() => t.silo.unreachable,
      SiloServerNeedsUpdate() => t.silo.needsUpdate,
      SiloServerFound(needsSetup: true) => t.silo.needsSetup,
      SiloServerFound() => null,
    };
    appLogger.i('Silo: server probe ${result.runtimeType}');
    if (error != null || result is! SiloServerFound) {
      setState(() => _step = _Editing(error));
      // The field lost focus while it was disabled for the probe.
      _addressFocus.requestFocus();
      return;
    }
    if (!await _consentToCleartext(result.origin)) return setState(() => _step = const _Editing());
    if (!mounted) return;
    setState(() => _step = const _Editing());
    final signedIn = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => SiloLoginScreen(origin: result.origin, targetProfile: widget.targetProfile),
      ),
    );
    if (signedIn == true && mounted) Navigator.of(context).pop(true);
  }

  /// A one-time approval per `http://` origin (`TvServerSetupViewModel.kt:178-239`).
  Future<bool> _consentToCleartext(Uri origin) async {
    if (origin.scheme != 'http') return true;
    final consent = await SiloApp.consent();
    final name = siloOrigin(origin);
    if (consent.isApproved(name)) return true;
    if (!mounted) return false;
    final confirmed = await showConfirmDialog(
      context,
      title: t.silo.cleartextTitle,
      message: t.silo.cleartextMessage(origin: name),
      confirmText: t.silo.cleartextConfirm,
    );
    if (!confirmed) return false;
    if (!await SiloApp.approveCleartext(name)) {
      if (mounted) setState(() => _step = _Editing(t.silo.cleartextUnsafe));
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final step = _step;
    final busy = step is _Probing;
    final error = step is _Editing ? step.error : null;
    return FocusedScrollScaffold(
      title: Text(t.silo.serverTitle),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: .stretch,
              children: [
                FocusableTextFormField(
                  controller: _address,
                  focusNode: _addressFocus,
                  tvTextInputPresentation: TvTextInputPresentation.platform,
                  autofocus: true,
                  tvTextInputAutoOpenBehavior: deferredUrlFieldAutoOpen,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  enabled: !busy,
                  onNavigateDown: () => _connectFocus.requestFocus(),
                  textInputAction: TextInputAction.go,
                  onFieldSubmitted: busy ? null : (_) => unawaited(_connect()),
                  decoration: InputDecoration(
                    labelText: t.silo.serverAddress,
                    hintText: t.silo.serverAddressHint,
                    errorText: error,
                    errorMaxLines: 3,
                    prefixIcon: const AppIcon(Symbols.link_rounded, fill: 1),
                  ),
                ),
                const SizedBox(height: 16),
                FocusableButton(
                  focusNode: _connectFocus,
                  useBackgroundFocus: true,
                  onNavigateUp: () => _addressFocus.requestFocus(),
                  onPressed: busy ? null : () => unawaited(_connect()),
                  child: FilledButton.icon(
                    onPressed: busy ? null : () => unawaited(_connect()),
                    icon: busy ? const LoadingIndicatorBox() : const AppIcon(Symbols.travel_explore_rounded, fill: 1),
                    label: Text(busy ? t.silo.checking : t.common.connect),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
