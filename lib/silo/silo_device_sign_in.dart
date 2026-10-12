import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'silo_contract_gate.dart';
import 'silo_http.dart';

const Duration siloDeviceMaxBackoff = Duration(seconds: 30);
const Duration _minPollInterval = Duration(seconds: 1);

/// A live device code from `POST /api/v2/auth/device/start`. [deviceCode] is
/// the polling secret and is never shown or logged.
class SiloDeviceCode {
  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final String verificationUriComplete;
  final Duration lifetime;
  final DateTime? serverExpiresAt;
  final Duration interval;

  const SiloDeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.verificationUriComplete,
    required this.lifetime,
    required this.interval,
    this.serverExpiresAt,
  });

  static SiloDeviceCode? fromJson(Object? json) {
    if (json is! Map) return null;
    final deviceCode = json['device_code'];
    final userCode = json['user_code'];
    if (deviceCode is! String || deviceCode.isEmpty || userCode == null) return null;
    final expiresIn = json['expires_in'];
    final interval = json['interval'];
    final seconds = interval is int ? interval : 1;
    return SiloDeviceCode(
      deviceCode: deviceCode,
      userCode: '$userCode',
      verificationUri: json['verification_uri'] is String ? json['verification_uri'] as String : '',
      verificationUriComplete: json['verification_uri_complete'] is String
          ? json['verification_uri_complete'] as String
          : '',
      lifetime: Duration(seconds: expiresIn is int && expiresIn > 0 ? expiresIn : 1),
      interval: seconds < 1 ? _minPollInterval : Duration(seconds: seconds),
      serverExpiresAt: DateTime.tryParse('${json['expires_at']}'),
    );
  }

  String get displayCode {
    final normalized = userCode.replaceAll(RegExp('[^A-Za-z0-9]'), '').toUpperCase();
    return normalized.length == 8 ? '${normalized.substring(0, 4)} ${normalized.substring(4)}' : normalized;
  }

  /// What the person types into a browser, per `DeviceCodeFormat.kt`.
  String get activateText {
    var text = verificationUri.trim();
    if (text.isEmpty) text = verificationUriComplete.split('?').first.trim();
    if (text.startsWith('https://')) text = text.substring('https://'.length);
    while (text.endsWith('/')) {
      text = text.substring(0, text.length - 1);
    }
    return text;
  }

  @override
  String toString() => 'SiloDeviceCode($displayCode)';
}

/// A token pair a sign-in produced and nothing has saved yet.
class SiloIssuedTokens {
  final String accessToken;
  final String refreshToken;

  /// Zero when the server left `expires_in` out, which the session reads as
  /// an unknown lifetime.
  final int expiresInSeconds;

  const SiloIssuedTokens({required this.accessToken, required this.refreshToken, required this.expiresInSeconds});

  static SiloIssuedTokens? fromJson(Object? json) {
    if (json is! Map) return null;
    final access = json['access_token'];
    final refresh = json['refresh_token'];
    if (access is! String || access.isEmpty || refresh is! String || refresh.isEmpty) return null;
    final expiresIn = json['expires_in'];
    return SiloIssuedTokens(
      accessToken: access,
      refreshToken: refresh,
      expiresInSeconds: expiresIn is int && expiresIn > 0 ? expiresIn : 0,
    );
  }

  @override
  String toString() => 'SiloIssuedTokens(redacted)';
}

/// What the login screen shows for its device code. Mirrors
/// `DeviceSignInState` in `S/repository/DeviceSignInMachine.kt`.
sealed class SiloDeviceSignInState {
  const SiloDeviceSignInState();
}

final class SiloDeviceGettingCode extends SiloDeviceSignInState {
  const SiloDeviceGettingCode();
}

final class SiloDeviceShowingCode extends SiloDeviceSignInState {
  final SiloDeviceCode code;

  /// An approver has looked the code up.
  final bool opened;

  /// This code replaced an expired one without the person asking.
  final bool renewed;

  const SiloDeviceShowingCode(this.code, {this.opened = false, this.renewed = false});
}

final class SiloDeviceApproved extends SiloDeviceSignInState {
  final SiloIssuedTokens tokens;

  const SiloDeviceApproved(this.tokens);
}

final class SiloDeviceDenied extends SiloDeviceSignInState {
  const SiloDeviceDenied();
}

/// Codes renewed for about an hour with nobody approving one.
final class SiloDevicePaused extends SiloDeviceSignInState {
  const SiloDevicePaused();
}

/// Still retrying, but calls have failed for a while. [code] is the last
/// code while the server may still hold it.
final class SiloDeviceUnreachable extends SiloDeviceSignInState {
  final SiloDeviceCode? code;

  const SiloDeviceUnreachable(this.code);
}

final class SiloDeviceTooManyRequests extends SiloDeviceSignInState {
  final SiloDeviceCode? code;

  const SiloDeviceTooManyRequests(this.code);
}

/// The server offers no device sign-in. Only the password form works.
final class SiloDeviceUnavailable extends SiloDeviceSignInState {
  const SiloDeviceUnavailable();
}

final class SiloDeviceUpdateRequired extends SiloDeviceSignInState {
  const SiloDeviceUpdateRequired();
}

/// An answer retrying cannot fix: a 4xx on start, an approval without
/// tokens, or an unknown status.
final class SiloDeviceFailed extends SiloDeviceSignInState {
  const SiloDeviceFailed();
}

class SiloDeviceSignInConfig {
  final Duration pauseAfter;
  final Duration startUnreachableAfter;
  final Duration pollUnreachableAfter;
  final Duration rateLimitedAfter;
  final Duration cancelTimeout;

  const SiloDeviceSignInConfig({
    this.pauseAfter = const Duration(minutes: 60),
    this.startUnreachableAfter = const Duration(seconds: 10),
    this.pollUnreachableAfter = const Duration(seconds: 30),
    this.rateLimitedAfter = const Duration(seconds: 60),
    this.cancelTimeout = const Duration(seconds: 5),
  });
}

/// The login screen's device code, from start to approval. Follows
/// `DeviceSignInMachine.kt` and `DeviceLoginRepository.kt:68-189`.
///
/// Every [run], [stop] and [abandon] supersedes the run before it. A call that
/// returns to a superseded run is dropped, so a slow reply can never bring
/// back a withdrawn code. [stop] is the one exception: a poll already in
/// flight still publishes its approval, because the server hands the tokens
/// out only once.
class SiloDeviceSignIn {
  final SiloHttp _http;
  final String _deviceName;
  final SiloDeviceSignInConfig _config;
  final Future<void> Function(Duration) _wait;
  final DateTime Function() _now;
  final ValueNotifier<SiloDeviceSignInState> _state = ValueNotifier(const SiloDeviceGettingCode());

  bool? _canCancel;
  SiloDeviceCode? _code;
  bool _opened = false;
  bool _renewed = false;
  DateTime _deadline = DateTime.fromMillisecondsSinceEpoch(0);
  Duration? _skew;
  Duration _interval = _minPollInterval;
  DateTime _lastActivity = DateTime.fromMillisecondsSinceEpoch(0);
  int _runId = 0;
  bool _stopRequested = false;
  bool _disposed = false;
  Completer<void>? _wake;

  SiloDeviceSignIn({
    required this._http,
    required this._deviceName,
    this._config = const SiloDeviceSignInConfig(),
    Future<void> Function(Duration)? wait,
    DateTime Function()? now,
  }) : _wait = wait ?? ((d) => Future<void>.delayed(d)),
       _now = now ?? DateTime.now;

  ValueListenable<SiloDeviceSignInState> get state => _state;

  /// Gets a code, or keeps the current one, and polls until the machine
  /// reaches a state that waits for the person or is stopped.
  Future<void> run() async {
    final id = ++_runId;
    _stopRequested = false;
    _lastActivity = _now();
    if (_canCancel == null) {
      final available = await _readCapability();
      if (id != _runId) return;
      if (!available) return _publish(const SiloDeviceUnavailable());
    }
    if (_code == null && !await _startCode(id, renewed: false)) return;
    await _pollLoop(id);
  }

  /// Stops polling and keeps the code, for when the screen is hidden.
  void stop() {
    _stopRequested = true;
    _wakeUp();
  }

  /// Supersedes every run and withdraws the code on the server. Best effort,
  /// bounded by [SiloDeviceSignInConfig.cancelTimeout].
  Future<void> abandon() async {
    _runId++;
    _stopRequested = true;
    _wakeUp();
    final code = _code;
    _code = null;
    if (code != null) await _withdraw(code);
  }

  void dispose() {
    _disposed = true;
    _runId++;
    _stopRequested = true;
    _wakeUp();
    _state.dispose();
  }

  Future<bool> _readCapability() async {
    try {
      final response = await _http.send(const SiloRequest.get('/api/v2/auth/device/capability', auth: SiloAuth.none));
      final json = response.statusCode == 200 ? _decode(response.body) : null;
      if (json is Map) {
        final available = json['state'] == 'available';
        _canCancel = available && json['cancel'] == true;
        return available;
      }
    } on SiloUpdateRequiredException {
      _canCancel = false;
      return true;
    } on Exception {
      // An unreadable capability leaves start to decide.
    }
    _canCancel = true;
    return true;
  }

  Future<bool> _startCode(int id, {required bool renewed}) async {
    _publish(const SiloDeviceGettingCode());
    final began = _now();
    var backoff = Duration.zero;
    while (true) {
      int? status;
      SiloDeviceCode? code;
      try {
        final response = await _http.send(
          SiloRequest.post(
            '/api/v2/auth/device/start',
            body: {'device_name': _deviceName, 'device_platform': _http.device.platform},
            auth: SiloAuth.none,
            single: true,
          ),
        );
        status = response.statusCode;
        if (status == 201) code = SiloDeviceCode.fromJson(_decode(response.body));
      } on SiloUpdateRequiredException {
        if (id == _runId) _publish(const SiloDeviceUpdateRequired());
        return false;
      } on Exception {
        status = null;
      }
      if (id != _runId) return false;
      if (code != null) {
        _install(code, renewed: renewed);
        return true;
      }
      if (status == 404 || status == 501) return _end(const SiloDeviceUnavailable());
      if (status == 410 || status == 426) return _end(const SiloDeviceUpdateRequired());
      if (status != null && status < 500 && status != 408 && status != 429) return _end(const SiloDeviceFailed());

      backoff = siloNextBackoff(backoff, _minPollInterval);
      final failingFor = _now().difference(began);
      if (status == 429 && failingFor >= _config.rateLimitedAfter) {
        _publish(const SiloDeviceTooManyRequests(null));
      } else if (failingFor >= _config.startUnreachableAfter) {
        _publish(const SiloDeviceUnreachable(null));
      }
      if (!await _sleep(id, backoff)) return false;
    }
  }

  void _install(SiloDeviceCode code, {required bool renewed}) {
    _code = code;
    _opened = false;
    _renewed = renewed;
    _deadline = _now().add(code.lifetime);
    final serverExpiry = code.serverExpiresAt;
    _skew = serverExpiry == null ? null : _deadline.difference(serverExpiry);
    _interval = code.interval;
    _publish(SiloDeviceShowingCode(code, renewed: renewed));
  }

  Future<void> _pollLoop(int id) async {
    var backoff = Duration.zero;
    DateTime? failingSince;
    DateTime? limitedSince;
    while (id == _runId) {
      final code = _code;
      if (code == null) return;

      int? status;
      Object? json;
      try {
        final response = await _http.send(
          SiloRequest.post(
            '/api/v2/auth/device/poll',
            body: {'device_code': code.deviceCode},
            auth: SiloAuth.none,
            single: true,
          ),
        );
        status = response.statusCode;
        if (status == 200) json = _decode(response.body);
      } on SiloUpdateRequiredException {
        if (id == _runId) _publish(const SiloDeviceUpdateRequired());
        return;
      } on Exception {
        status = null;
      }
      if (id != _runId) return;

      if (status == 200) {
        if (json is! Map) return _finish(const SiloDeviceFailed());
        backoff = Duration.zero;
        failingSince = limitedSince = null;
        switch (json['status']) {
          case 'pending':
            _readPending(json);
            _publish(SiloDeviceShowingCode(code, opened: _opened, renewed: _renewed));
            if (_expired) {
              if (!await _renew(id, withdraw: true)) return;
            } else if (!await _sleep(id, _clampToDeadline(_interval))) {
              return;
            }
          case 'approved':
            final tokens = SiloIssuedTokens.fromJson(json['tokens']);
            return _finish(tokens == null ? const SiloDeviceFailed() : SiloDeviceApproved(tokens));
          case 'denied':
            return _finish(const SiloDeviceDenied());
          case 'expired' || 'consumed' || 'canceled':
            if (!await _renew(id, withdraw: false)) return;
          default:
            return _finish(const SiloDeviceFailed());
        }
        continue;
      }

      if (status == 410 || status == 426) return _finish(const SiloDeviceUpdateRequired());
      final transient = status == null || status == 408 || status == 429 || status >= 500;
      if (!transient) {
        if (!await _renew(id, withdraw: false)) return;
        backoff = Duration.zero;
        continue;
      }

      backoff = siloNextBackoff(backoff, _interval);
      final now = _now();
      failingSince ??= now;
      limitedSince = status == 429 ? (limitedSince ?? now) : null;
      if (limitedSince != null && now.difference(limitedSince) >= _config.rateLimitedAfter) {
        _publish(SiloDeviceTooManyRequests(code));
      } else if (now.difference(failingSince) >= _config.pollUnreachableAfter) {
        _publish(SiloDeviceUnreachable(code));
      }
      // Past the deadline without an answer the server may still hold the
      // code, so it is withdrawn before a new one is asked for.
      if (_expired) {
        if (!await _renew(id, withdraw: true)) return;
        backoff = Duration.zero;
        failingSince = limitedSince = null;
      } else if (!await _sleep(id, _clampToDeadline(backoff))) {
        return;
      }
    }
  }

  bool get _expired => !_now().isBefore(_deadline);

  /// A pending reply may move the poll interval and extend, never shorten,
  /// the deadline. Its `expires_at` goes through the start reply's own
  /// `expires_at`/`expires_in` pair so clock skew cancels out.
  void _readPending(Map<Object?, Object?> json) {
    final pendingExpiry = DateTime.tryParse('${json['expires_at']}');
    final skew = _skew;
    if (pendingExpiry != null && skew != null) {
      final extended = pendingExpiry.add(skew);
      if (extended.isAfter(_deadline)) _deadline = extended;
    }
    final after = json['poll_after'];
    if (after is int) _interval = after < 1 ? _minPollInterval : Duration(seconds: after);
    if (json['opened'] == true && !_opened) {
      _opened = true;
      _lastActivity = _now();
    }
  }

  /// Replaces the code. [withdraw] cancels it on the server first, for a code
  /// the server may still hold.
  Future<bool> _renew(int id, {required bool withdraw}) async {
    final code = _code;
    _code = null;
    if (withdraw && code != null) await _withdraw(code);
    if (id != _runId) return false;
    if (_now().difference(_lastActivity) >= _config.pauseAfter) return _end(const SiloDevicePaused());
    return _startCode(id, renewed: true);
  }

  Future<void> _withdraw(SiloDeviceCode code) async {
    if (_canCancel == false) return;
    try {
      await _http
          .send(
            SiloRequest.post(
              '/api/v2/auth/device/cancel',
              body: {'device_code': code.deviceCode},
              auth: SiloAuth.none,
              single: true,
              timeout: _config.cancelTimeout,
            ),
          )
          .timeout(_config.cancelTimeout);
    } on Object {
      // Best effort: an unreachable server cannot approve the code either.
    }
  }

  Duration _clampToDeadline(Duration wait) {
    final left = _deadline.difference(_now());
    if (left <= Duration.zero) return Duration.zero;
    return wait < left ? wait : left;
  }

  Future<bool> _sleep(int id, Duration duration) async {
    if (_stopRequested || id != _runId) return false;
    final wake = _wake = Completer<void>();
    await Future.any([_wait(duration), wake.future]);
    return !_stopRequested && id == _runId;
  }

  void _wakeUp() {
    final wake = _wake;
    if (wake != null && !wake.isCompleted) wake.complete();
  }

  void _finish(SiloDeviceSignInState state) {
    _code = null;
    _publish(state);
  }

  bool _end(SiloDeviceSignInState state) {
    _finish(state);
    return false;
  }

  void _publish(SiloDeviceSignInState state) {
    if (!_disposed) _state.value = state;
  }
}

/// Backoff from [interval], doubling to [siloDeviceMaxBackoff], never under
/// one second.
Duration siloNextBackoff(Duration current, Duration interval) {
  if (current <= Duration.zero) {
    if (interval < _minPollInterval) return _minPollInterval;
    return interval > siloDeviceMaxBackoff ? siloDeviceMaxBackoff : interval;
  }
  final doubled = current * 2;
  return doubled > siloDeviceMaxBackoff ? siloDeviceMaxBackoff : doubled;
}

Object? _decode(String body) {
  try {
    return jsonDecode(body);
  } on FormatException {
    return null;
  }
}
