import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../utils/app_logger.dart';

import 'silo_contract_gate.dart';
import 'silo_device_sign_in.dart';
import 'silo_headers.dart';
import 'silo_http.dart';
import 'silo_problem.dart';
import 'silo_profiles.dart';
import 'silo_session.dart';

enum SiloSignInErrorKind {
  usernameRequired,
  passwordRequired,
  invalidCredentials,
  accountDisabled,
  rateLimited,
  providerUnavailable,
  localLoginDisabled,
  notPermitted,
  passwordExpired,
  accountRequired,
  identityChanged,
  updateRequired,
  network,
  server,
}

class SiloSignInError {
  final SiloSignInErrorKind kind;

  /// The server's problem `detail`, shown for [SiloSignInErrorKind.server].
  final String detail;

  const SiloSignInError(this.kind, [this.detail = '']);

  /// Problem code first, then status, per `ExternalSignInModels.kt:231-245`.
  factory SiloSignInError.fromResponse(int status, SiloProblem? problem) {
    final kind = switch (problem?.code) {
      'local_login_disabled' => SiloSignInErrorKind.localLoginDisabled,
      'not_permitted' => SiloSignInErrorKind.notPermitted,
      'password_expired' => SiloSignInErrorKind.passwordExpired,
      'provider_unavailable' => SiloSignInErrorKind.providerUnavailable,
      'account_required' => SiloSignInErrorKind.accountRequired,
      'rate_limited' => SiloSignInErrorKind.rateLimited,
      _ => switch (status) {
        429 => SiloSignInErrorKind.rateLimited,
        401 => SiloSignInErrorKind.invalidCredentials,
        403 => SiloSignInErrorKind.accountDisabled,
        503 => SiloSignInErrorKind.providerUnavailable,
        _ => SiloSignInErrorKind.server,
      },
    };
    return SiloSignInError(kind, problem?.detail ?? '');
  }
}

sealed class SiloPasswordResult {
  const SiloPasswordResult();
}

final class SiloPasswordAccepted extends SiloPasswordResult {
  final SiloIssuedTokens tokens;
  final String username;

  const SiloPasswordAccepted(this.tokens, this.username);
}

final class SiloPasswordRefused extends SiloPasswordResult {
  final SiloSignInError error;

  const SiloPasswordRefused(this.error);
}

/// `POST /api/v2/auth/login`. Saves nothing; the caller commits the tokens.
Future<SiloPasswordResult> siloPasswordLogin(SiloHttp silo, String username, String password) async {
  if (username.trim().isEmpty) return const SiloPasswordRefused(SiloSignInError(SiloSignInErrorKind.usernameRequired));
  if (password.isEmpty) return const SiloPasswordRefused(SiloSignInError(SiloSignInErrorKind.passwordRequired));
  final SiloResponse response;
  try {
    response = await silo.send(
      SiloRequest.post(
        '/api/v2/auth/login',
        body: {'username': username.trim(), 'password': password},
        auth: SiloAuth.none,
        single: true,
      ),
    );
  } on SiloUpdateRequiredException {
    return const SiloPasswordRefused(SiloSignInError(SiloSignInErrorKind.updateRequired));
  } on Exception {
    return const SiloPasswordRefused(SiloSignInError(SiloSignInErrorKind.network));
  }
  if (response.statusCode != 200) {
    return SiloPasswordRefused(SiloSignInError.fromResponse(response.statusCode, response.problem));
  }
  final json = _decode(response.body);
  final tokens = SiloIssuedTokens.fromJson(json);
  if (tokens == null || json is! Map) {
    return SiloPasswordRefused(SiloSignInError.fromResponse(response.statusCode, null));
  }
  final user = json['user'];
  final name = user is Map && user['username'] is String ? user['username'] as String : username.trim();
  return SiloPasswordAccepted(tokens, name);
}

sealed class SiloPasswordState {
  const SiloPasswordState();
}

final class SiloPasswordIdle extends SiloPasswordState {
  const SiloPasswordIdle();
}

final class SiloPasswordSubmitting extends SiloPasswordState {
  const SiloPasswordSubmitting();
}

final class SiloPasswordFailed extends SiloPasswordState {
  final SiloSignInError error;

  const SiloPasswordFailed(this.error);
}

/// Where the login screen is. The device code and password form run side by
/// side only in [SiloLoginRacing].
sealed class SiloLoginPhase {
  const SiloLoginPhase();
}

/// Reading the server's identity before anything can be signed in.
final class SiloLoginOpening extends SiloLoginPhase {
  const SiloLoginOpening();
}

final class SiloLoginUnreachable extends SiloLoginPhase {
  const SiloLoginUnreachable();
}

final class SiloLoginRacing extends SiloLoginPhase {
  final SiloDeviceSignInState device;
  final SiloPasswordState password;

  const SiloLoginRacing({required this.device, required this.password});
}

/// One flow won and its tokens are being saved.
final class SiloLoginCommitting extends SiloLoginPhase {
  const SiloLoginCommitting();
}

final class SiloLoginSignedIn extends SiloLoginPhase {
  final String username;

  const SiloLoginSignedIn(this.username);
}

/// The server a sign-in lands on, known once the login screen has read it.
class SiloServerIdentity {
  final String serverId;
  final String serverName;

  const SiloServerIdentity(this.serverId, this.serverName);
}

/// The login screen's state machine. Starts the device code on open and
/// offers the password beside it; the first finisher wins
/// (`TvLoginViewModel.kt:225-250`, `:797-801`). Every commit is fenced by the
/// session generation captured before its sign-in call (port note 9).
class SiloLoginController extends ChangeNotifier {
  final Uri origin;
  final SiloHeaders device;
  final Future<SiloSessionController> Function(String serverId) sessionFor;
  final String deviceName;
  final http.Client? _client;

  /// One connection pool for every call the screen makes, like the app-wide
  /// client in `NetworkModule.kt:17`, so the device code reuses the
  /// connection the identity read opened instead of a new TLS handshake.
  final http.Client _connections;
  final bool Function(String origin)? _cleartextApproved;
  final SiloDeviceSignInConfig _deviceConfig;
  final Future<void> Function(Duration)? _wait;
  final DateTime Function()? _now;

  SiloLoginPhase _phase = const SiloLoginOpening();
  SiloPasswordState _password = const SiloPasswordIdle();
  SiloServerIdentity? _server;
  SiloHttp? _http;
  SiloDeviceSignIn? _deviceSignIn;
  int _deviceGeneration = 0;
  bool _claimed = false;
  SiloIssuedTokens? _heldApproval;
  bool _disposed = false;

  SiloLoginController({
    required Uri origin,
    required this.device,
    required this.sessionFor,
    required this.deviceName,
    this._client,
    this._cleartextApproved,
    this._deviceConfig = const SiloDeviceSignInConfig(),
    this._wait,
    this._now,
  }) : origin = Uri.parse(siloOrigin(origin)),
       _connections = _client ?? SiloHttp.newSiloHttpClient();

  SiloLoginPhase get phase => _phase;
  SiloServerIdentity? get server => _server;
  SiloHttp? get siloHttp => _http;

  /// Reads the server identity, then starts the device code. Safe to call
  /// again from [SiloLoginUnreachable].
  Future<void> open() async {
    if (_phase is! SiloLoginOpening && _phase is! SiloLoginUnreachable) return;
    _setPhase(const SiloLoginOpening());
    final probe = SiloHttp(
      origin: origin,
      session: await SiloSessionController.load(MemorySiloSessionStore()),
      device: device,
      client: _connections,
      cleartextApproved: _cleartextApproved,
    );
    final identity = await readSiloServerIdentity(probe);
    if (_disposed) return;
    if (identity == null) return _setPhase(const SiloLoginUnreachable());
    final session = await sessionFor(identity.serverId);
    if (_disposed || _phase is! SiloLoginOpening) return;
    _server = identity;
    final silo = _http = SiloHttp(
      origin: origin,
      session: session,
      device: device,
      client: _connections,
      cleartextApproved: _cleartextApproved,
    );
    final deviceSignIn = _deviceSignIn = SiloDeviceSignIn(
      http: silo,
      deviceName: deviceName,
      config: _deviceConfig,
      wait: _wait,
      now: _now,
    );
    deviceSignIn.state.addListener(_onDeviceState);
    _deviceGeneration = session.generation;
    _race();
    unawaited(deviceSignIn.run());
  }

  Future<void> submitPassword(String username, String password) async {
    final silo = _http;
    if (silo == null || _phase is! SiloLoginRacing || _password is SiloPasswordSubmitting) return;
    final expected = silo.session.generation;
    _password = const SiloPasswordSubmitting();
    _race();
    final result = await siloPasswordLogin(silo, username, password);
    if (_disposed || _claimed) return;
    switch (result) {
      case SiloPasswordRefused(:final error):
        appLogger.i('Silo: password refused (${error.kind.name})');
        _password = SiloPasswordFailed(error);
        _race();
      case SiloPasswordAccepted(:final tokens, :final username):
        _claimed = true;
        _setPhase(const SiloLoginCommitting());
        if (!await _commit(silo, tokens, expected)) {
          _claimed = false;
          _password = const SiloPasswordFailed(SiloSignInError(SiloSignInErrorKind.identityChanged));
          _race();
          final held = _heldApproval;
          _heldApproval = null;
          if (held != null) await _onApproved(held);
          return;
        }
        await _deviceSignIn?.abandon();
        _setPhase(SiloLoginSignedIn(username));
    }
  }

  /// Withdraws the device code unless a sign-in already landed. Call when the
  /// person leaves the screen.
  Future<void> leave() async {
    if (_phase is SiloLoginSignedIn) return;
    await _deviceSignIn?.abandon();
  }

  /// The screen is hidden. Polling stops, but a poll already in flight still
  /// delivers its approval, because the server hands tokens out once.
  void pause() => _deviceSignIn?.stop();

  /// The screen is back. Polls at once and renews the code if it expired.
  void resume() {
    final deviceSignIn = _deviceSignIn;
    if (deviceSignIn == null || _claimed || _phase is! SiloLoginRacing) return;
    if (deviceSignIn.state.value
        case SiloDeviceShowingCode() || SiloDeviceUnreachable() || SiloDeviceTooManyRequests()) {
      unawaited(deviceSignIn.run());
    }
  }

  /// Gets a fresh code after the machine stopped on denial, failure or pause.
  void restartDeviceCode() {
    final deviceSignIn = _deviceSignIn;
    if (deviceSignIn == null || _claimed) return;
    unawaited(() async {
      await deviceSignIn.abandon();
      if (_disposed || _claimed) return;
      _deviceGeneration = _http!.session.generation;
      await deviceSignIn.run();
    }());
  }

  void _onDeviceState() {
    final state = _deviceSignIn?.state.value;
    if (state is SiloDeviceApproved) {
      unawaited(_onApproved(state.tokens));
    } else if (!_claimed) {
      _race();
    }
  }

  Future<void> _onApproved(SiloIssuedTokens tokens) async {
    final silo = _http;
    if (silo == null) return;
    if (_claimed) {
      _heldApproval = tokens;
      return;
    }
    appLogger.i('Silo: device code approved');
    _claimed = true;
    _setPhase(const SiloLoginCommitting());
    if (!await _commit(silo, tokens, _deviceGeneration)) {
      _claimed = false;
      _password = const SiloPasswordFailed(SiloSignInError(SiloSignInErrorKind.identityChanged));
      _race();
      restartDeviceCode();
      return;
    }
    var username = '';
    try {
      final me = await silo.send(const SiloRequest.get('/api/v2/account/me'));
      if (me.statusCode == 200) username = SiloAccount.fromJson(me.json())?.username ?? '';
    } on Exception {
      // The name is decoration; the session is already saved.
    }
    _setPhase(SiloLoginSignedIn(username));
  }

  /// Saves [tokens] only if no identity change landed since [expected], and
  /// confirms the save was the only one.
  Future<bool> _commit(SiloHttp silo, SiloIssuedTokens tokens, int expected) async {
    try {
      await silo.session.replaceAccountSession(
        origin: silo.origin.toString(),
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        expiresInSeconds: tokens.expiresInSeconds,
        expectedGeneration: expected,
      );
    } on SiloIdentityChangedException {
      return false;
    }
    return silo.session.generation == expected + 1;
  }

  void _race() {
    final deviceSignIn = _deviceSignIn;
    if (deviceSignIn == null) return;
    _setPhase(SiloLoginRacing(device: deviceSignIn.state.value, password: _password));
  }

  void _setPhase(SiloLoginPhase phase) {
    if (_disposed) return;
    _phase = phase;
    notifyListeners();
  }

  void _closeConnections() {
    if (_client == null) _connections.close();
  }

  @override
  void dispose() {
    _disposed = true;
    final deviceSignIn = _deviceSignIn;
    if (deviceSignIn == null) {
      _closeConnections();
    } else {
      deviceSignIn.state.removeListener(_onDeviceState);
      unawaited(
        deviceSignIn.abandon().whenComplete(() {
          deviceSignIn.dispose();
          _closeConnections();
        }),
      );
    }
    super.dispose();
  }
}

/// `GET /api/v2/system/identity` and the branding name, read in parallel.
/// Null when the server cannot be identified.
Future<SiloServerIdentity?> readSiloServerIdentity(SiloHttp silo) async {
  Future<Object?> read(String path, Duration bound) async {
    try {
      final response = await silo
          .send(SiloRequest('GET', path, auth: SiloAuth.none, single: true, timeout: bound))
          .timeout(bound);
      return response.statusCode == 200 ? _decode(response.body) : null;
    } on Object {
      return null;
    }
  }

  final results = await Future.wait([
    read('/api/v2/system/identity', const Duration(seconds: 8)),
    read('/api/v2/theme/branding', const Duration(seconds: 8)),
  ]);
  final identity = results[0];
  final serverId = identity is Map && identity['server_id'] is String ? (identity['server_id'] as String).trim() : '';
  if (serverId.isEmpty) return null;
  final branding = results[1];
  final name = branding is Map && branding['server_name'] is String ? (branding['server_name'] as String).trim() : '';
  return SiloServerIdentity(serverId, name.isEmpty ? silo.origin.host : name);
}

Object? _decode(String body) {
  try {
    return jsonDecode(body);
  } on FormatException {
    return null;
  }
}
