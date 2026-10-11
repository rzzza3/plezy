import 'dart:async';
import 'dart:convert';

import '../utils/serial_future_queue.dart';

class SiloTokens {
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  /// Null when the issuer's intended lifetime is unknown, which turns off
  /// proactive refresh until the next issuance records one.
  final Duration? lifetime;

  const SiloTokens({required this.accessToken, required this.refreshToken, required this.expiresAt, this.lifetime});

  factory SiloTokens.issued({
    required String accessToken,
    required String refreshToken,
    required int expiresInSeconds,
    required DateTime now,
  }) {
    final lifetime = Duration(seconds: expiresInSeconds);
    return SiloTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(now.add(lifetime).millisecondsSinceEpoch, isUtc: true),
      lifetime: lifetime,
    );
  }
}

/// One signed-in identity on one server. Immutable; every change produces a
/// new value that the controller persists as a single write.
class SiloSession {
  final String origin;
  final SiloTokens tokens;
  final String? profileId;
  final String? profileToken;

  const SiloSession({required this.origin, required this.tokens, this.profileId, this.profileToken});

  SiloSession withTokens(SiloTokens tokens) =>
      SiloSession(origin: origin, tokens: tokens, profileId: profileId, profileToken: profileToken);

  SiloSession withProfile(String? id, String? token) =>
      SiloSession(origin: origin, tokens: tokens, profileId: id, profileToken: id == null ? null : token);

  Map<String, Object?> toJson() => {
    'origin': origin,
    'access_token': tokens.accessToken,
    'refresh_token': tokens.refreshToken,
    'token_expiry_epoch_ms': tokens.expiresAt.millisecondsSinceEpoch,
    if (tokens.lifetime case final lifetime?) 'token_lifetime_ms': lifetime.inMilliseconds,
    'profile_id': ?profileId,
    'profile_token': ?profileToken,
  };

  static SiloSession? fromJson(Object? json) {
    if (json is! Map) return null;
    final origin = json['origin'];
    final access = json['access_token'];
    final refresh = json['refresh_token'];
    final expiry = json['token_expiry_epoch_ms'];
    if (origin is! String || access is! String || refresh is! String || expiry is! int) return null;
    final lifetime = json['token_lifetime_ms'];
    final profileId = json['profile_id'];
    final profileToken = json['profile_token'];
    return SiloSession(
      origin: origin,
      tokens: SiloTokens(
        accessToken: access,
        refreshToken: refresh,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(expiry, isUtc: true),
        lifetime: lifetime is int ? Duration(milliseconds: lifetime) : null,
      ),
      profileId: profileId is String ? profileId : null,
      profileToken: profileId is String && profileToken is String ? profileToken : null,
    );
  }
}

/// What the vault holds: the session, if any, and the identity generation it
/// was written under. Both travel in one write so they can never disagree.
class SiloSessionState {
  final int generation;
  final SiloSession? session;

  const SiloSessionState({required this.generation, this.session});

  static const SiloSessionState initial = SiloSessionState(generation: 0);

  String encode() => jsonEncode({'v': 1, 'generation': generation, 'session': session?.toJson()});

  static SiloSessionState decode(String raw) {
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      return initial;
    }
    if (json is! Map || json['v'] != 1) return initial;
    final generation = json['generation'];
    return SiloSessionState(
      generation: generation is int ? generation : 0,
      session: SiloSession.fromJson(json['session']),
    );
  }
}

abstract interface class SiloSessionStore {
  Future<SiloSessionState> read();
  Future<void> write(SiloSessionState state);
}

class MemorySiloSessionStore implements SiloSessionStore {
  SiloSessionState state;

  MemorySiloSessionStore([this.state = SiloSessionState.initial]);

  @override
  Future<SiloSessionState> read() async => state;

  @override
  Future<void> write(SiloSessionState state) async => this.state = state;
}

class SiloIdentityChangedException implements Exception {
  final int expected;
  final int actual;

  const SiloIdentityChangedException({required this.expected, required this.actual});

  @override
  String toString() => 'SiloIdentityChangedException: expected generation $expected, found $actual';
}

/// Refresh results. Only [SiloRefreshRejected] ends the session.
sealed class SiloRefreshOutcome {
  const SiloRefreshOutcome();
}

final class SiloRefreshed extends SiloRefreshOutcome {
  final SiloSession session;

  /// False when another caller already refreshed and this one only picked up
  /// its token.
  final bool usedNetwork;

  const SiloRefreshed(this.session, {required this.usedNetwork});
}

/// The session moved underneath the refresh (sign-out, sign-in, profile or
/// server change), so its result belongs to nobody and was dropped.
final class SiloRefreshNotAttempted extends SiloRefreshOutcome {
  const SiloRefreshNotAttempted();
}

/// Server error, gateway failure or network error. The tokens are kept.
final class SiloRefreshTransient extends SiloRefreshOutcome {
  final int? status;
  final bool providerUnavailable;

  const SiloRefreshTransient({this.status, this.providerUnavailable = false});
}

/// 400, 401 or 403 from `/api/v2/auth/refresh`. The session was cleared.
final class SiloRefreshRejected extends SiloRefreshOutcome {
  final int status;

  const SiloRefreshRejected(this.status);
}

bool shouldRefreshProactively({required Duration remaining, required Duration? lifetime, required Duration margin}) {
  if (remaining <= Duration.zero) return true;
  if (lifetime == null || lifetime <= Duration.zero) return false;
  final clamped = margin < Duration.zero ? Duration.zero : margin;
  final half = lifetime ~/ 2;
  return remaining <= (clamped < half ? clamped : half);
}

/// Owns the in-memory session and every write of it. In-memory state changes
/// synchronously so concurrent callers always see the latest identity; vault
/// writes run in order behind it.
class SiloSessionController {
  final SiloSessionStore _store;
  final DateTime Function() _now;
  final SerialFutureQueue _writes = SerialFutureQueue();
  final StreamController<void> _expired = StreamController<void>.broadcast(sync: true);
  SiloSessionState _state;

  SiloSessionController._(this._store, this._state, this._now);

  static Future<SiloSessionController> load(SiloSessionStore store, {DateTime Function()? now}) async =>
      SiloSessionController._(store, await store.read(), now ?? DateTime.now);

  SiloSessionState get state => _state;
  SiloSession? get session => _state.session;
  int get generation => _state.generation;
  DateTime now() => _now().toUtc();

  /// Fires when the server repudiated the refresh token. A user sign-out
  /// never fires it.
  Stream<void> get sessionExpired => _expired.stream;

  /// Commits a fresh sign-in. With [expectedGeneration], refuses when another
  /// identity change landed since the caller captured it.
  Future<SiloSession> replaceAccountSession({
    required String origin,
    required String accessToken,
    required String refreshToken,
    required int expiresInSeconds,
    int? expectedGeneration,
  }) async {
    if (expectedGeneration != null && expectedGeneration != _state.generation) {
      throw SiloIdentityChangedException(expected: expectedGeneration, actual: _state.generation);
    }
    final session = SiloSession(
      origin: origin,
      tokens: SiloTokens.issued(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresInSeconds: expiresInSeconds,
        now: now(),
      ),
    );
    await _commit(SiloSessionState(generation: _state.generation + 1, session: session));
    return session;
  }

  /// A token rotation is not an identity change, so the generation stays.
  Future<SiloSession?> saveRefreshedTokens({
    required String accessToken,
    required String refreshToken,
    required int expiresInSeconds,
  }) async {
    final current = _state.session;
    if (current == null) return null;
    final session = current.withTokens(
      SiloTokens.issued(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresInSeconds: expiresInSeconds,
        now: now(),
      ),
    );
    await _commit(SiloSessionState(generation: _state.generation, session: session));
    return session;
  }

  Future<void> selectProfile(String? id, String? token) async {
    final current = _state.session;
    if (current == null) return;
    await _commit(SiloSessionState(generation: _state.generation + 1, session: current.withProfile(id, token)));
  }

  Future<void> signOut() => _commit(SiloSessionState(generation: _state.generation + 1));

  Future<void> invalidate() async {
    await _commit(SiloSessionState(generation: _state.generation + 1));
    _expired.add(null);
  }

  Future<void> _commit(SiloSessionState next) {
    _state = next;
    return _writes.run(() => _store.write(next));
  }

  Future<void> close() => _expired.close();
}
