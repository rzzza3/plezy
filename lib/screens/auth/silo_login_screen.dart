import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../focus/focusable_button.dart';
import '../../focus/focusable_text_field.dart';
import '../../i18n/strings.g.dart';
import '../../mixins/controller_disposer_mixin.dart';
import '../../profiles/profile.dart';
import '../../services/silo_client.dart';
import '../../silo/silo_app.dart';
import '../../silo/silo_device_sign_in.dart';
import '../../silo/silo_sign_in.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/app_logger.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../../widgets/loading_indicator_box.dart';
import '../profile/silo_profile_screen.dart';

/// Device code and password side by side; the first to finish wins
/// (`TvLoginScreen.kt`, `TvLoginViewModel.kt`). Pops with `true` once a
/// profile is bound.
class SiloLoginScreen extends StatefulWidget {
  final Uri origin;
  final Profile? targetProfile;

  const SiloLoginScreen({super.key, required this.origin, this.targetProfile});

  @override
  State<SiloLoginScreen> createState() => _SiloLoginScreenState();
}

class _SiloLoginScreenState extends State<SiloLoginScreen> with ControllerDisposerMixin {
  late final _username = createTextEditingController();
  late final _password = createTextEditingController();
  final _usernameFocus = FocusNode(debugLabel: 'SiloLogin:usernameFocus');
  final _passwordFocus = FocusNode(debugLabel: 'SiloLogin:passwordFocus');
  SiloLoginController? _controller;
  AppLifecycleListener? _lifecycle;
  bool _leftForProfiles = false;

  @override
  void initState() {
    super.initState();
    appLogger.i('Silo: login screen opened');
    unawaited(_start());
  }

  Future<void> _start() async {
    final device = await SiloApp.device();
    final consent = await SiloApp.consent();
    if (!mounted) return;
    final controller = SiloLoginController(
      origin: widget.origin,
      device: device,
      sessionFor: SiloApp.session,
      deviceName: device.name,
      cleartextApproved: consent.isApproved,
    )..addListener(_onPhase);
    _lifecycle = AppLifecycleListener(onHide: controller.pause, onShow: controller.resume);
    setState(() => _controller = controller);
    await controller.open();
  }

  void _onPhase() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final phase = controller.phase;
    if (phase is SiloLoginRacing && phase.device is SiloDeviceShowingCode) {
      appLogger.d('Silo: device code shown');
    }
    if (phase is SiloLoginSignedIn && !_leftForProfiles) {
      _leftForProfiles = true;
      appLogger.i('Silo: signed in');
      unawaited(_openProfiles(controller));
    }
    setState(() {});
  }

  /// "Signed in as" stays up for a second (`TvLoginViewModel.kt:709-715`).
  Future<void> _openProfiles(SiloLoginController controller) async {
    await Future<void>.delayed(const Duration(seconds: 1));
    final silo = controller.siloHttp;
    final server = controller.server;
    if (silo == null || server == null) return;
    if (!mounted) return signOutSiloSession(silo);
    final entered = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => SiloProfileScreen(silo: silo, server: server, targetProfile: widget.targetProfile),
      ),
    );
    if (entered != true) {
      // Backing out of the picker abandons this sign-in, so the server keeps
      // no session for a device that never entered a profile.
      await signOutSiloSession(silo);
    }
    if (mounted) Navigator.of(context).pop(entered == true);
  }

  @override
  void dispose() {
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _lifecycle?.dispose();
    final controller = _controller;
    if (controller != null) {
      controller.removeListener(_onPhase);
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final server = controller?.server;
    return FocusedScrollScaffold(
      title: Text(server == null ? t.silo.serverTitle : t.silo.signInTitle(server: server.serverName)),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: .fromLTRB(24, 16, 24, 24 + MediaQuery.paddingOf(context).bottom),
            child: Center(child: _body(context, controller)),
          ),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, SiloLoginController? controller) {
    final phase = controller?.phase;
    return switch (phase) {
      null || SiloLoginOpening() => _Waiting(t.silo.connecting),
      SiloLoginUnreachable() => _Unreachable(onRetry: () => unawaited(controller!.open())),
      SiloLoginCommitting() => _Waiting(t.silo.signingIn),
      SiloLoginSignedIn(:final username) => _SignedIn(username),
      SiloLoginRacing(:final device, :final password) => LayoutBuilder(
        builder: (context, constraints) {
          final code = _CodePanel(state: device, onNewCode: controller!.restartDeviceCode);
          final form = _passwordForm(context, controller, password);
          if (constraints.maxWidth < 720) {
            return Column(
              mainAxisSize: .min,
              crossAxisAlignment: .stretch,
              children: [code, const SizedBox(height: 32), form],
            );
          }
          return Row(
            crossAxisAlignment: .center,
            children: [
              Expanded(child: code),
              const SizedBox(width: 48),
              Expanded(child: form),
            ],
          );
        },
      ),
    };
  }

  Widget _passwordForm(BuildContext context, SiloLoginController controller, SiloPasswordState state) {
    final theme = Theme.of(context);
    final busy = state is SiloPasswordSubmitting;
    void submit() => unawaited(controller.submitPassword(_username.text, _password.text));
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: [
        Text(t.silo.passwordHeading, style: theme.textTheme.titleMedium),
        const SizedBox(height: 16),
        FocusableTextFormField(
          controller: _username,
          focusNode: _usernameFocus,
          autofocus: true,
          tvTextInputAutoOpenBehavior: deferredUrlFieldAutoOpen,
          autocorrect: false,
          enableSuggestions: false,
          enabled: !busy,
          textInputAction: TextInputAction.next,
          onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
          decoration: InputDecoration(
            labelText: t.silo.username,
            prefixIcon: const AppIcon(Symbols.person_rounded, fill: 1),
          ),
        ),
        const SizedBox(height: 12),
        FocusableTextFormField(
          controller: _password,
          focusNode: _passwordFocus,
          obscureText: true,
          enabled: !busy,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: busy ? null : (_) => submit(),
          decoration: InputDecoration(
            labelText: t.silo.password,
            prefixIcon: const AppIcon(Symbols.lock_rounded, fill: 1),
          ),
        ),
        if (state case SiloPasswordFailed(:final error)) ...[
          const SizedBox(height: 12),
          Text(_errorText(error), style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 16),
        FocusableButton(
          useBackgroundFocus: true,
          onPressed: busy ? null : submit,
          child: FilledButton.icon(
            onPressed: busy ? null : submit,
            icon: busy ? const LoadingIndicatorBox() : const AppIcon(Symbols.login_rounded, fill: 1),
            label: Text(t.silo.signIn),
          ),
        ),
      ],
    );
  }
}

String _errorText(SiloSignInError error) => switch (error.kind) {
  SiloSignInErrorKind.usernameRequired => t.silo.errors.usernameRequired,
  SiloSignInErrorKind.passwordRequired => t.silo.errors.passwordRequired,
  SiloSignInErrorKind.invalidCredentials => t.silo.errors.invalidCredentials,
  SiloSignInErrorKind.accountDisabled => t.silo.errors.accountDisabled,
  SiloSignInErrorKind.rateLimited => t.silo.errors.rateLimited,
  SiloSignInErrorKind.providerUnavailable => t.silo.errors.providerUnavailable,
  SiloSignInErrorKind.localLoginDisabled => t.silo.errors.localLoginDisabled,
  SiloSignInErrorKind.notPermitted => t.silo.errors.notPermitted,
  SiloSignInErrorKind.passwordExpired => t.silo.errors.passwordExpired,
  SiloSignInErrorKind.accountRequired => t.silo.errors.accountRequired,
  SiloSignInErrorKind.identityChanged => t.silo.errors.identityChanged,
  SiloSignInErrorKind.updateRequired => t.silo.errors.updateRequired,
  SiloSignInErrorKind.network => t.silo.errors.network,
  SiloSignInErrorKind.server => error.detail.isEmpty ? t.silo.errors.server : error.detail,
};

class _CodePanel extends StatelessWidget {
  final SiloDeviceSignInState state;
  final VoidCallback onNewCode;

  const _CodePanel({required this.state, required this.onNewCode});

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      SiloDeviceGettingCode() || SiloDeviceApproved() => _Waiting(t.silo.codeGetting),
      SiloDeviceShowingCode(:final code, :final opened, :final renewed) => _Code(
        code: code,
        note: opened ? t.silo.codeOpened : (renewed ? t.silo.codeRenewed : null),
      ),
      SiloDeviceUnreachable(:final code) => _codeOrMessage(code, t.silo.codeUnreachable),
      SiloDeviceTooManyRequests(:final code) => _codeOrMessage(code, t.silo.codeRateLimited),
      SiloDeviceUnavailable() => _Message(t.silo.codeUnavailable),
      SiloDeviceUpdateRequired() => _Message(t.silo.codeUpdateRequired),
      SiloDeviceDenied() => _Message(t.silo.codeDenied, action: onNewCode),
      SiloDeviceFailed() => _Message(t.silo.codeFailed, action: onNewCode),
      SiloDevicePaused() => _Message(t.silo.codePaused, action: onNewCode),
    };
  }

  Widget _codeOrMessage(SiloDeviceCode? code, String message) =>
      code == null ? _Message(message) : _Code(code: code, note: message, warning: true);
}

class _Code extends StatelessWidget {
  final SiloDeviceCode code;
  final String? note;
  final bool warning;

  const _Code({required this.code, this.note, this.warning = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.7);
    final qr = code.verificationUriComplete;
    return Column(
      mainAxisSize: .min,
      children: [
        Text(
          t.silo.codeVisit,
          style: theme.textTheme.bodyLarge?.copyWith(color: muted),
          textAlign: .center,
        ),
        const SizedBox(height: 4),
        Text(code.activateText, style: theme.textTheme.titleLarge, textAlign: .center),
        const SizedBox(height: 4),
        Text(
          t.silo.codeEnter,
          style: theme.textTheme.bodyLarge?.copyWith(color: muted),
          textAlign: .center,
        ),
        const SizedBox(height: 12),
        Text(
          code.displayCode,
          style: theme.textTheme.displayMedium?.copyWith(
            fontWeight: .bold,
            letterSpacing: 6,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          textAlign: .center,
        ),
        if (qr.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            t.silo.codeScan,
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            textAlign: .center,
          ),
          const SizedBox(height: 12),
          SizedBox.square(
            dimension: 168,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(tokens(context).radiusMd),
              child: QrImageView(data: qr, size: 168, version: QrVersions.auto, backgroundColor: Colors.white),
            ),
          ),
        ],
        if (note != null) ...[
          const SizedBox(height: 16),
          Text(
            note!,
            style: theme.textTheme.bodyMedium?.copyWith(color: warning ? theme.colorScheme.error : muted),
            textAlign: .center,
          ),
        ],
      ],
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  final VoidCallback? action;

  const _Message(this.text, {this.action});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      children: [
        Text(text, style: Theme.of(context).textTheme.bodyLarge, textAlign: .center),
        if (action != null) ...[
          const SizedBox(height: 16),
          FocusableButton(
            onPressed: action,
            child: OutlinedButton(onPressed: action, child: Text(t.silo.codeNew)),
          ),
        ],
      ],
    );
  }
}

class _Waiting extends StatelessWidget {
  final String text;

  const _Waiting(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: .min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
          textAlign: .center,
        ),
      ],
    );
  }
}

class _Unreachable extends StatelessWidget {
  final VoidCallback onRetry;

  const _Unreachable({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      children: [
        Text(t.silo.unreachable, style: Theme.of(context).textTheme.bodyLarge, textAlign: .center),
        const SizedBox(height: 16),
        FocusableButton(
          autofocus: true,
          onPressed: onRetry,
          child: OutlinedButton(onPressed: onRetry, child: Text(t.common.retry)),
        ),
      ],
    );
  }
}

class _SignedIn extends StatelessWidget {
  final String username;

  const _SignedIn(this.username);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: .min,
      children: [
        AppIcon(Symbols.check_circle_rounded, fill: 1, size: 48, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          username.isEmpty ? t.silo.signingIn : t.silo.signedInAs(username: username),
          style: theme.textTheme.titleLarge,
          textAlign: .center,
        ),
      ],
    );
  }
}
