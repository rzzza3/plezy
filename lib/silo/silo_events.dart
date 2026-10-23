import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../media/ids.dart';
import '../media/library_change_event.dart';
import '../utils/app_logger.dart';
import '../utils/web_socket_connect.dart';
import 'silo_http.dart';

/// A pending connection: [channel] resolves to an *established* channel or
/// throws; [cancel] aborts a connect still in flight and releases its
/// transport, and is a no-op once [channel] has settled.
typedef LibraryEventConnection = ({Future<WebSocketChannel> channel, void Function() cancel});

const String siloEventsProtocol = 'silo.events.v2';
const List<String> siloEventChannels = ['user_state', 'catalog'];

/// One server frame the home acts on (`S/network/HomeRealtimeClient.kt:24-40`).
sealed class SiloEventFrame {
  const SiloEventFrame();
}

/// Connected or reconnected. The catch-up point for anything missed.
final class SiloSubscribed extends SiloEventFrame {
  final List<String> channels;
  final List<String> rejected;

  const SiloSubscribed({this.channels = const [], this.rejected = const []});
}

/// `user_state.changed`, account-scoped (`S/network/HomeRealtimeClient.kt:14-22`).
final class SiloUserStateChanged extends SiloEventFrame {
  final String profileId;
  final String? contentId;
  final String? seriesId;
  final String change;

  const SiloUserStateChanged({required this.profileId, this.contentId, this.seriesId, required this.change});
}

/// Any `catalog` channel event.
final class SiloCatalogChanged extends SiloEventFrame {
  const SiloCatalogChanged();
}

/// Null for hello, snapshots, errors, foreign channels, unknown events and
/// malformed JSON (`S/network/HomeRealtimeClient.kt:76-101`).
SiloEventFrame? parseSiloEventFrame(Object? raw) {
  if (raw is! String) return null;
  final Object? json;
  try {
    json = jsonDecode(raw);
  } on FormatException {
    return null;
  }
  if (json is! Map<String, Object?>) return null;
  switch (json['type']) {
    case 'subscribed':
      return SiloSubscribed(
        channels: [for (final channel in _list(json['channels'])) ?_nonBlank(channel)],
        rejected: [
          for (final rejected in _list(json['rejected']))
            if (rejected is Map<String, Object?>) ?_nonBlank(rejected['channel']),
        ],
      );
    case 'event':
      switch (json['channel']) {
        case 'user_state':
          final data = json['data'];
          if (json['event'] != 'user_state.changed' || data is! Map<String, Object?>) return null;
          final profileId = data['profile_id'];
          final change = data['change'];
          if (profileId is! String || change is! String) return null;
          return SiloUserStateChanged(
            profileId: profileId,
            contentId: _nonBlank(data['content_id']),
            seriesId: _nonBlank(data['series_id']),
            change: change,
          );
        case 'catalog':
          return const SiloCatalogChanged();
      }
  }
  return null;
}

List<Object?> _list(Object? value) => value is List ? value : const [];

String? _nonBlank(Object? value) => value is String && value.isNotEmpty ? value : null;

/// Foreign-profile changes are dropped. An unknown active profile refreshes
/// rather than risk a stale home (`S/network/HomeRealtimeClient.kt:108-114`).
bool siloHomeRefreshTrigger(SiloEventFrame frame, String? activeProfileId) => switch (frame) {
  SiloSubscribed() || SiloCatalogChanged() => true,
  SiloUserStateChanged(:final profileId) => activeProfileId == null || profileId == activeProfileId,
};

/// A single-use socket proof from `POST /api/v2/events/ws-ticket`.
class SiloWsTicket {
  final String _value;
  final Duration expiresIn;
  final Duration maxConnection;

  SiloWsTicket._(this._value, this.expiresIn, this.maxConnection);

  /// Null unless the server's answer passes `validTicket`
  /// (`S/network/apiv2/EventsSocketV2Api.kt:78-80`).
  static SiloWsTicket? parse(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final value = json['ticket'];
    final expiresIn = json['expires_in'];
    final maxConnection = json['max_connection_seconds'];
    if (json['protocol'] != siloEventsProtocol ||
        value is! String ||
        !_ticketToken.hasMatch(value) ||
        expiresIn is! int ||
        expiresIn < 1 ||
        expiresIn > 30 ||
        maxConnection is! int ||
        maxConnection < 1 ||
        maxConnection > 300) {
      return null;
    }
    return SiloWsTicket._(value, Duration(seconds: expiresIn), Duration(seconds: maxConnection));
  }

  static final RegExp _ticketToken = RegExp(r"^[A-Za-z0-9!#$%&'*+\-.^_`|~]+$");

  /// The upgrade's only credential (`S/network/apiv2/EventsSocketV2Api.kt:93-97`).
  List<String> get protocols => [siloEventsProtocol, 'silo.ticket.$_value'];

  @override
  String toString() => 'SiloWsTicket(<redacted>)';
}

/// `ws`/`wss` on the server origin, path and channels only
/// (`S/network/apiv2/EventsSocketV2Api.kt:82-92`). The upgrade carries the
/// device headers and no credential (`S/network/AuthInterceptorImpl.kt:409-414`).
Uri siloEventsUri(Uri origin) => Uri(
  scheme: origin.scheme == 'https' ? 'wss' : 'ws',
  host: origin.host,
  port: origin.hasPort ? origin.port : null,
  path: '/api/v2/events/ws',
  queryParameters: {'channels': siloEventChannels.join(',')},
);

typedef SiloSocketConnect =
    LibraryEventConnection Function(Uri uri, List<String> protocols, Map<String, String> headers);

LibraryEventConnection connectSiloSocket(Uri uri, List<String> protocols, Map<String, String> headers) {
  final attempt = WebSocketConnectAttempt(
    uri,
    connectTimeout: const Duration(seconds: 10),
    headers: headers,
    protocols: protocols,
  );
  return (
    channel: attempt.socket.then((socket) {
      socket.pingInterval = const Duration(seconds: 30);
      return IOWebSocketChannel(socket);
    }),
    cancel: attempt.cancel,
  );
}

enum SiloEventsPhase { idle, fetchingTicket, connecting, subscribed, backingOff, closed }

/// The live-home socket. Each attempt mints one ticket and makes one upgrade,
/// reconnects back off from 1 s to 30 s, and triggers feed one 2 s trailing
/// debouncer (`S/repository/HomeRealtimeCoordinator.kt:28-67`). It emits a
/// [LibraryChangeEvent] with [LibraryChangeEvent.homeChanged] per quiet window.
/// [LibraryEventService] stops it on pause, sign-out and profile switch, as
/// `T/home/HomeRealtimeForegroundStarter.kt:34-66` does.
class SiloEvents implements LibraryEventChannel {
  SiloEvents({
    required this.http,
    required this.serverId,
    this.onHomeStale,
    SiloSocketConnect? connect,
    Future<void> Function(Duration delay)? wait,
    this.debounce = const Duration(seconds: 2),
  }) : _connect = connect ?? connectSiloSocket,
       _wait = wait ?? Future<void>.delayed;

  static const Duration initialBackoff = Duration(seconds: 1);
  static const Duration maxBackoff = Duration(seconds: 30);

  final SiloHttp http;
  final ServerId serverId;

  /// Runs before each emitted event, so the refetch it causes is not served
  /// from a cached read.
  final void Function()? onHomeStale;
  final Duration debounce;
  final SiloSocketConnect _connect;
  final Future<void> Function(Duration delay) _wait;

  final _events = StreamController<LibraryChangeEvent>.broadcast();
  SiloEventsPhase _phase = SiloEventsPhase.idle;
  int _run = 0;
  LibraryEventConnection? _pending;
  WebSocketChannel? _channel;
  Completer<void>? _closed;
  Timer? _debounceTimer;
  bool _catalogPending = false;

  SiloEventsPhase get phase => _phase;

  @override
  Stream<LibraryChangeEvent> get events => _events.stream;

  @override
  void start() {
    if (_phase != SiloEventsPhase.idle) return;
    unawaited(_loop(++_run));
  }

  @override
  void stop() {
    if (_phase == SiloEventsPhase.closed) return;
    ++_run;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _catalogPending = false;
    _teardown();
    if (_phase != SiloEventsPhase.idle) _enter(SiloEventsPhase.idle);
  }

  @override
  void dispose() {
    if (_phase == SiloEventsPhase.closed) return;
    stop();
    _enter(SiloEventsPhase.closed);
    unawaited(_events.close());
  }

  void _enter(SiloEventsPhase phase) {
    _phase = phase;
    appLogger.i('Silo events: ${phase.name}');
  }

  Future<void> _loop(int run) async {
    var backoff = initialBackoff;
    while (run == _run) {
      if (await _attempt(run)) backoff = initialBackoff;
      if (run != _run) return;
      _enter(SiloEventsPhase.backingOff);
      await _wait(backoff);
      final doubled = backoff * 2;
      backoff = doubled > maxBackoff ? maxBackoff : doubled;
    }
  }

  /// One ticket, one upgrade, never retried with the same ticket
  /// (`S/network/apiv2/EventsSocketV2Api.kt:37-71`). True once a frame decoded.
  Future<bool> _attempt(int run) async {
    _enter(SiloEventsPhase.fetchingTicket);
    final generation = http.session.generation;
    if (http.session.session == null) return false;
    bool current() => run == _run && http.session.generation == generation;
    final minted = Stopwatch()..start();
    final ticket = await _fetchTicket();
    if (ticket == null || !current() || minted.elapsed >= ticket.expiresIn) return false;

    _enter(SiloEventsPhase.connecting);
    final connection = _connect(siloEventsUri(http.origin), ticket.protocols, http.device.toMap());
    _pending = connection;
    final WebSocketChannel channel;
    try {
      channel = await connection.channel;
      await channel.ready;
    } on Object catch (error) {
      if (run == _run) appLogger.i('Silo events: upgrade failed (${error.runtimeType})');
      return false;
    } finally {
      if (identical(_pending, connection)) _pending = null;
    }
    if (!current() || channel.protocol != siloEventsProtocol) {
      unawaited(channel.sink.close());
      return false;
    }

    _channel = channel;
    final closed = _closed = Completer<void>();
    var established = false;
    final lifetime = Timer(ticket.maxConnection, _teardown);
    final authority = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!current()) _teardown();
    });
    final frames = channel.stream.listen(
      (raw) {
        if (!current()) return _teardown();
        final frame = parseSiloEventFrame(raw);
        if (frame == null) return;
        established = true;
        if (frame is SiloSubscribed) {
          _enter(SiloEventsPhase.subscribed);
          appLogger.i('Silo events: ${frame.channels.length} channels, ${frame.rejected.length} rejected');
        } else if (frame is SiloUserStateChanged) {
          appLogger.i('Silo events: user_state.changed (${frame.change})');
        } else {
          appLogger.i('Silo events: catalog event');
        }
        if (siloHomeRefreshTrigger(frame, http.session.session?.profileId)) _trigger(frame is SiloCatalogChanged);
      },
      onError: (Object _) => _teardown(),
      onDone: _teardown,
      cancelOnError: true,
    );
    channel.sink.add(jsonEncode({'type': 'subscribe', 'channels': siloEventChannels}));
    await closed.future;
    lifetime.cancel();
    authority.cancel();
    unawaited(frames.cancel());
    return established;
  }

  Future<SiloWsTicket?> _fetchTicket() async {
    try {
      final response = await http.send(const SiloRequest.post('/api/v2/events/ws-ticket'));
      final ticket = response.statusCode == 200 ? SiloWsTicket.parse(jsonDecode(response.body)) : null;
      if (ticket == null) appLogger.i('Silo events: ticket unavailable (status ${response.statusCode})');
      return ticket;
    } on Object catch (error) {
      appLogger.i('Silo events: ticket unavailable (${error.runtimeType})');
      return null;
    }
  }

  void _teardown() {
    _pending?.cancel();
    _pending = null;
    final channel = _channel;
    _channel = null;
    if (channel != null) unawaited(channel.sink.close());
    final closed = _closed;
    _closed = null;
    if (closed != null && !closed.isCompleted) closed.complete();
  }

  void _trigger(bool catalog) {
    _catalogPending |= catalog;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, _flush);
  }

  void _flush() {
    _debounceTimer = null;
    final catalog = _catalogPending;
    _catalogPending = false;
    if (_phase == SiloEventsPhase.closed) return;
    appLogger.i('Silo events: home refetch');
    onHomeStale?.call();
    _events.add(LibraryChangeEvent(serverId: serverId, homeChanged: true, itemsUpdated: catalog));
  }
}
