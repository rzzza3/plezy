import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../focus/focusable_button.dart';
import '../../focus/focusable_text_field.dart';
import '../../i18n/strings.g.dart';
import '../../mixins/controller_disposer_mixin.dart';
import '../../models/seerr/seerr_public_settings.dart';
import '../../models/seerr/seerr_session.dart';
import '../../providers/seerr_account_provider.dart';
import '../../services/seerr/seerr_exceptions.dart';
import '../../theme/mono_tokens.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../../widgets/loading_indicator_box.dart';
import 'async_form_state_mixin.dart';

/// Two-step Seerr connect flow:
///   1. Probe the instance URL (`/settings/public`), racing https/http/default
///      port candidates for schemeless input, but never settling on plaintext
///      while TLS may still answer.
///   2. Sign in with a local Seerr account (email and password). The
///      instance must have local sign-in enabled.
///
/// The finished [SeerrSession] is handed to [SeerrAccountProvider.adoptSession]
/// and the screen pops.
class SeerrConnectScreen extends StatefulWidget {
  const SeerrConnectScreen({super.key});

  @override
  State<SeerrConnectScreen> createState() => _SeerrConnectScreenState();
}

class _SeerrConnectScreenState extends State<SeerrConnectScreen> with AsyncFormStateMixin, ControllerDisposerMixin {
  late final _urlController = createTextEditingController();
  late final _identifierController = createTextEditingController();
  late final _passwordController = createTextEditingController();
  final _urlFocus = FocusNode(debugLabel: 'SeerrConnect:Url');
  final _continueFocus = FocusNode(debugLabel: 'SeerrConnect:Continue');
  final _changeServerFocus = FocusNode(debugLabel: 'SeerrConnect:ChangeServer');
  final _identifierFocus = FocusNode(debugLabel: 'SeerrConnect:Identifier');
  final _passwordFocus = FocusNode(debugLabel: 'SeerrConnect:Password');
  final _formKey = GlobalKey<FormState>();

  SeerrPublicSettings? _instance;
  String _baseUrl = '';

  @override
  void dispose() {
    _urlFocus.dispose();
    _continueFocus.dispose();
    _changeServerFocus.dispose();
    _identifierFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _probe() async {
    final input = _urlController.text.trim();
    if (input.isEmpty) {
      setErrorText(t.addServer.required);
      return;
    }
    await runAsync<void>(() async {
      final account = context.read<SeerrAccountProvider>();
      // Schemeless input is common ("seerr.example.com", "192.168.1.5:5055"):
      // race https, plain http, and the default install port instead of
      // assuming https and failing every plain-HTTP LAN instance.
      final reached = await account.authService.probeFirstReachable(input);
      if (!mounted) return;
      setState(() {
        _instance = reached.settings;
        _baseUrl = reached.baseUrl;
      });
      if (reached.settings.localLogin) requestFocusAfterFrame(_identifierFocus);
    }, errorMapper: _describeError);
  }

  Future<void> _signInWithCredentials() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await runAsync<void>(() async {
      final account = context.read<SeerrAccountProvider>();
      final session = await account.authService.signInWithLocal(
        baseUrl: _baseUrl,
        email: _identifierController.text.trim(),
        password: _passwordController.text,
      );
      await _finish(account, session);
    }, errorMapper: _describeError);
  }

  Future<void> _finish(SeerrAccountProvider account, SeerrSession session) async {
    // The probe already answered /settings/public; carry its label and the
    // product discriminator (MediaStatus 6/7 decode per product) into the
    // persisted session.
    await account.adoptSession(session.copyWith(instanceLabel: _instance?.instanceLabel, product: _instance?.product));
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  String _describeError(Object e) => switch (e) {
    SeerrUrlException(:final message, :final display) => display ?? message,
    SeerrAuthException(:final message, :final display) => display ?? message,
    SeerrProxyException(:final display) => display,
    _ => t.addServer.couldNotReachServer(error: e.toString()),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FocusedScrollScaffold(
      title: Text(t.seerr.connectTitle),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverToBoxAdapter(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _instance == null ? _buildUrlStep(theme) : _buildSignInStep(theme),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildUrlStep(ThemeData theme) {
    return [
      FocusableTextFormField(
        controller: _urlController,
        focusNode: _urlFocus,
        autofocus: true,
        tvTextInputAutoOpenBehavior: deferredUrlFieldAutoOpen,
        keyboardType: TextInputType.url,
        autocorrect: false,
        enableSuggestions: false,
        enabled: !busy,
        onNavigateDown: () => _continueFocus.requestFocus(),
        textInputAction: TextInputAction.go,
        onFieldSubmitted: busy ? null : (_) => _probe(),
        decoration: InputDecoration(
          labelText: t.seerr.serverUrl,
          // URL example — intentionally not localized.
          hintText: 'https://seerr.example.com',
          helperText: t.seerr.serverUrlHelper,
          prefixIcon: const AppIcon(Symbols.link_rounded, fill: 1),
        ),
      ),
      const SizedBox(height: 16),
      FocusableButton(
        focusNode: _continueFocus,
        useBackgroundFocus: true,
        onNavigateUp: () => _urlFocus.requestFocus(),
        onPressed: busy ? null : _probe,
        child: FilledButton.icon(
          onPressed: busy ? null : _probe,
          icon: busy ? const LoadingIndicatorBox() : const AppIcon(Symbols.travel_explore_rounded, fill: 1),
          label: Text(t.seerr.checkServer),
        ),
      ),
      ...buildInlineError(theme),
    ];
  }

  List<Widget> _buildSignInStep(ThemeData theme) {
    final instance = _instance!;
    return [
      _buildInstanceCard(theme, instance),
      const SizedBox(height: 16),
      if (instance.localLogin)
        ..._buildCredentialFields(theme)
      else
        Text(t.seerr.noSignInMethods, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)),
      ...buildInlineError(theme),
    ];
  }

  List<Widget> _buildCredentialFields(ThemeData theme) {
    return [
      FocusableTextFormField(
        controller: _identifierController,
        focusNode: _identifierFocus,
        autocorrect: false,
        enableSuggestions: false,
        enabled: !busy,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        onFieldSubmitted: busy ? null : (_) => _passwordFocus.requestFocus(),
        decoration: InputDecoration(labelText: t.seerr.email, prefixIcon: const AppIcon(Symbols.mail_rounded, fill: 1)),
        validator: (v) => v == null || v.trim().isEmpty ? t.addServer.required : null,
      ),
      const SizedBox(height: 12),
      FocusableTextFormField(
        controller: _passwordController,
        focusNode: _passwordFocus,
        obscureText: true,
        enabled: !busy,
        textInputAction: TextInputAction.done,
        onFieldSubmitted: busy ? null : (_) => _signInWithCredentials(),
        decoration: InputDecoration(
          labelText: t.addServer.password,
          prefixIcon: const AppIcon(Symbols.lock_rounded, fill: 1),
        ),
        validator: (v) => v == null || v.isEmpty ? t.addServer.required : null,
      ),
      const SizedBox(height: 16),
      FocusableButton(
        useBackgroundFocus: true,
        onPressed: busy ? null : _signInWithCredentials,
        child: FilledButton.icon(
          onPressed: busy ? null : _signInWithCredentials,
          icon: busy ? const LoadingIndicatorBox() : const AppIcon(Symbols.login_rounded, fill: 1),
          label: Text(t.addServer.signIn),
        ),
      ),
    ];
  }

  Widget _buildInstanceCard(ThemeData theme, SeerrPublicSettings instance) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(tokens(context).radiusMd),
      ),
      child: Row(
        children: [
          const AppIcon(Symbols.cloud_done_rounded, fill: 1),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(instance.instanceLabel, style: theme.textTheme.titleSmall),
                Text(
                  _baseUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ),
          FocusableButton(
            focusNode: _changeServerFocus,
            useBackgroundFocus: true,
            onPressed: busy ? null : _resetToUrlStep,
            child: TextButton(onPressed: busy ? null : _resetToUrlStep, child: Text(t.addServer.change)),
          ),
        ],
      ),
    );
  }

  void _resetToUrlStep() {
    setState(() {
      _instance = null;
      _identifierController.clear();
      _passwordController.clear();
    });
  }
}
