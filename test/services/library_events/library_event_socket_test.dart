import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/library_change_event.dart';
import 'package:plezy/services/library_events/library_event_socket.dart';
import 'package:plezy/services/library_events/plex_library_event_socket.dart';

/// Ephemeral loopback websocket server standing in for a media server's
/// notification endpoint. Real protocol boundary, torn down unconditionally.
class _NotificationServer {
  _NotificationServer._(this._server);

  final HttpServer _server;
  final List<WebSocket> sockets = [];
  final List<Uri> requestUris = [];
  final _connections = StreamController<WebSocket>.broadcast();

  String get baseUrl => 'http://${_server.address.address}:${_server.port}';

  static Future<_NotificationServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final notification = _NotificationServer._(server);
    server.listen((request) async {
      notification.requestUris.add(request.uri);
      final socket = await WebSocketTransformer.upgrade(request);
      notification.sockets.add(socket);
      socket.listen((_) {}, onDone: socket.close);
      notification._connections.add(socket);
    });
    return notification;
  }

  /// The next socket to connect (or an already-connected one).
  Future<WebSocket> nextConnection() async {
    if (sockets.isNotEmpty) return sockets.last;
    return _connections.stream.first;
  }

  void send(WebSocket socket, Map<String, dynamic> message) => socket.add(jsonEncode(message));

  Future<void> close() async {
    for (final socket in sockets) {
      await socket.close();
    }
    await _server.close(force: true);
    await _connections.close();
  }
}

/// Frames captured live from Plex 1.43 during one library scan (2026-08-31).
Map<String, dynamic> _plexTimeline(List<Map<String, dynamic>> entries) => {
  'NotificationContainer': {'type': 'timeline', 'size': entries.length, 'TimelineEntry': entries},
};

Map<String, dynamic> _plexTimelineEntry({
  required int state,
  int type = 1,
  String? sectionId = '1',
  String? metadataState,
}) => {
  'identifier': 'com.plexapp.plugins.library',
  'sectionID': ?sectionId,
  'itemID': '10141',
  'type': type,
  'title': 'Prefix Test (2024)',
  'state': state,
  'metadataState': ?metadataState,
  'updatedAt': 1788180088,
};

const _plexPlayingFrame = {
  'NotificationContainer': {
    'type': 'playing',
    'size': 1,
    'PlaySessionStateNotification': [
      {'sessionKey': '3', 'ratingKey': '9940', 'key': '/library/metadata/9940', 'state': 'paused'},
    ],
  },
};

void main() {
  final servers = <_NotificationServer>[];
  final channels = <LibraryEventChannel>[];

  Future<_NotificationServer> startServer() async {
    final server = await _NotificationServer.start();
    servers.add(server);
    return server;
  }

  T track<T extends LibraryEventChannel>(T channel) {
    channels.add(channel);
    return channel;
  }

  tearDown(() async {
    for (final channel in channels) {
      channel.dispose();
    }
    channels.clear();
    for (final server in servers) {
      await server.close();
    }
    servers.clear();
  });

  PlexLibraryEventSocket plexSocket(
    _NotificationServer server, {
    Duration debounce = const Duration(milliseconds: 100),
  }) => track(
    PlexLibraryEventSocket(
      serverId: ServerId('plex_1'),
      baseUrl: () => server.baseUrl,
      token: () => 'token-1',
      debounce: debounce,
      retryBaseDelay: const Duration(milliseconds: 50),
    ),
  );

  test('websocket URIs preserve a reverse-proxy path prefix', () {
    final plex = track(
      PlexLibraryEventSocket(
        serverId: ServerId('plex_1'),
        baseUrl: () => 'https://proxy.example/plex',
        token: () => 'token-1',
        debounce: Duration.zero,
      ),
    );
    expect(plex.buildUri().path, '/plex/:/websockets/notifications');
    expect(plex.buildUri().scheme, 'wss');
  });

  group('PlexLibraryEventSocket', () {
    test('first settled entry emits immediately; the rest of the flood coalesces', () async {
      final server = await startServer();
      final channel = plexSocket(server);
      final events = <LibraryChangeEvent>[];
      channel.events.listen(events.add);
      channel.start();
      final socket = await server.nextConnection();

      expect(server.requestUris.single.path, '/:/websockets/notifications');
      expect(server.requestUris.single.queryParameters['X-Plex-Token'], 'token-1');

      // The measured state walk for one new item, plus unrelated session
      // noise: only the settled state-5 entries may schedule the event.
      server.send(socket, _plexPlayingFrame);
      for (final state in [0, 1, 2, 3, 4]) {
        server.send(socket, _plexTimeline([_plexTimelineEntry(state: state, metadataState: 'created')]));
      }
      server.send(socket, _plexTimeline([_plexTimelineEntry(state: 5)]));
      server.send(socket, _plexTimeline([_plexTimelineEntry(state: 5)]));
      server.send(socket, _plexTimeline([_plexTimelineEntry(state: 5, sectionId: '2')]));

      // Leading edge (Plex Web parity): the first settled entry surfaces
      // without waiting out the debounce.
      final first = await channel.events.first.timeout(const Duration(milliseconds: 500));
      expect(first.serverId, 'plex_1');
      expect(first.libraryIds, {'1'});
      expect(first.itemsAdded, isTrue);
      expect(first.itemsUpdated, isTrue);
      expect(first.itemsRemoved, isFalse);

      // The remaining settled entries merge into exactly one trailing event.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(events, hasLength(2));
      expect(events[1].libraryIds, {'1', '2'});
    });

    test('an entry without a section absorbs the named ones in its window, in either order', () async {
      for (final unnamedFirst in [true, false]) {
        final server = await startServer();
        final channel = plexSocket(server);
        final events = <LibraryChangeEvent>[];
        channel.events.listen(events.add);
        channel.start();
        final socket = await server.nextConnection();

        // Prime the window so everything below coalesces into one trailing
        // event instead of surfacing on the leading edge.
        server.send(socket, _plexTimeline([_plexTimelineEntry(state: 5, sectionId: '9')]));
        await channel.events.first.timeout(const Duration(milliseconds: 500));

        final unnamed = _plexTimeline([_plexTimelineEntry(state: 5, sectionId: null)]);
        final named = _plexTimeline([_plexTimelineEntry(state: 5, sectionId: '1')]);
        server.send(socket, unnamedFirst ? unnamed : named);
        server.send(socket, unnamedFirst ? named : unnamed);
        server.send(socket, _plexTimeline([_plexTimelineEntry(state: 5, sectionId: '2')]));

        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(events, hasLength(2), reason: 'unnamedFirst=$unnamedFirst');
        expect(events[1].targetsWholeServer, isTrue, reason: 'unnamedFirst=$unnamedFirst');
        expect(events[1].libraryIds, isEmpty, reason: 'unnamedFirst=$unnamedFirst');

        // The absorbed scope does not leak into the next window.
        server.send(socket, _plexTimeline([_plexTimelineEntry(state: 5, sectionId: '3')]));
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(events, hasLength(3), reason: 'unnamedFirst=$unnamedFirst');
        expect(events[2].libraryIds, {'3'}, reason: 'unnamedFirst=$unnamedFirst');
      }
    });

    test('a sustained stream emits once per window instead of starving', () async {
      final server = await startServer();
      final channel = plexSocket(server, debounce: const Duration(milliseconds: 150));
      final events = <LibraryChangeEvent>[];
      channel.events.listen(events.add);
      channel.start();
      final socket = await server.nextConnection();

      // Frames every 80 ms for ~1.2 s. A trailing-reset debounce would emit
      // nothing until the stream stops; the min-interval throttle emits a
      // leading event plus one per elapsed window.
      for (var i = 0; i < 15; i++) {
        server.send(socket, _plexTimeline([_plexTimelineEntry(state: 5)]));
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }

      expect(events.length, greaterThanOrEqualTo(2), reason: 'must not starve while frames keep arriving');
      expect(events.length, lessThanOrEqualTo(10), reason: 'at most one event per 150 ms window, not per frame');
    });

    test('settled deletion entry reports itemsRemoved', () async {
      final server = await startServer();
      final channel = plexSocket(server);
      channel.start();
      final socket = await server.nextConnection();

      server.send(socket, _plexTimeline([_plexTimelineEntry(state: 5, type: -1)]));

      final event = await channel.events.first.timeout(const Duration(seconds: 5));
      expect(event.itemsRemoved, isTrue);
      expect(event.itemsAdded, isFalse);
      expect(event.removedItemIds, {'10141'}, reason: 'deletion ids ride along for in-place drops');
    });

    test('a malformed frame does not kill the channel', () async {
      final server = await startServer();
      final channel = plexSocket(server);
      channel.start();
      final socket = await server.nextConnection();

      socket.add('this is not json');
      socket.add('[1,2,3]');
      server.send(socket, _plexTimeline([_plexTimelineEntry(state: 5)]));

      final event = await channel.events.first.timeout(const Duration(seconds: 5));
      expect(event.itemsAdded, isTrue);
    });

    test('reconnects after the server drops the connection', () async {
      final server = await startServer();
      final channel = plexSocket(server);
      channel.start();
      final first = await server.nextConnection();

      await first.close();
      // Backoff is 50ms; the second connection must arrive on its own.
      await _waitFor(() => server.sockets.length >= 2);

      server.send(server.sockets[1], _plexTimeline([_plexTimelineEntry(state: 5)]));
      final event = await channel.events.first.timeout(const Duration(seconds: 5));
      expect(event.itemsAdded, isTrue);
    });

    test('stop() prevents reconnecting', () async {
      final server = await startServer();
      final channel = plexSocket(server);
      channel.start();
      await server.nextConnection();

      channel.stop();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(server.sockets, hasLength(1), reason: 'no reconnect after stop');
      expect(channel.isRunning, isFalse);
    });

    test('a websocket upgrade landing after the connect deadline is closed, not leaked', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final releaseUpgrade = Completer<void>();
      final lateSocketClosed = Completer<void>();
      server.listen((request) async {
        await releaseUpgrade.future;
        final socket = await WebSocketTransformer.upgrade(request);
        // The peer's close frame ends the inbound stream; `socket.done` only
        // settles once this side closes too, so close on it and let `done`
        // be the observation.
        socket.listen((_) {}, onDone: socket.close);
        unawaited(socket.done.then((_) => lateSocketClosed.complete()));
      });

      final channel = track(
        PlexLibraryEventSocket(
          serverId: ServerId('plex_1'),
          baseUrl: () => 'http://${server.address.address}:${server.port}',
          token: () => 'token-1',
          debounce: Duration.zero,
          maxConnectAttempts: 0,
          channelFactory: libraryEventChannelFactory(connectTimeout: const Duration(milliseconds: 200)),
        ),
      );
      channel.start();
      // The deadline fires while the upgrade is still held back; with no
      // retries left the socket gives up.
      await _waitFor(() => !channel.isRunning);

      releaseUpgrade.complete();
      await lateSocketClosed.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => fail('late websocket was never closed by the client'),
      );
    });

    test('stop() while the connect is pending releases the transport', () async {
      // Accepts TCP and never answers the upgrade.
      final blackHole = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final stalled = <Socket>[];
      final accepting = blackHole.listen(stalled.add);
      addTearDown(() async {
        await accepting.cancel();
        for (final socket in stalled) {
          socket.destroy();
        }
        await blackHole.close();
      });

      final channel = track(
        PlexLibraryEventSocket(
          serverId: ServerId('plex_1'),
          baseUrl: () => 'http://${blackHole.address.address}:${blackHole.port}',
          token: () => 'token-1',
          debounce: Duration.zero,
          channelFactory: libraryEventChannelFactory(connectTimeout: const Duration(seconds: 30)),
        ),
      );
      channel.start();
      await _waitFor(() => stalled.isNotEmpty);
      final peerClosed = stalled.single.drain<void>();

      channel.stop();
      await peerClosed.timeout(
        const Duration(seconds: 5),
        onTimeout: () => fail('the pending connect was not cancelled by stop()'),
      );
      expect(channel.isRunning, isFalse);
    });

    test('stop disposes an established transport published after its channel handoff', () async {
      final server = await startServer();
      final established = Completer<void>();
      final release = Completer<void>();
      final channel = track(
        PlexLibraryEventSocket(
          serverId: ServerId('plex_1'),
          baseUrl: () => server.baseUrl,
          token: () => 'token-1',
          debounce: Duration.zero,
          channelFactory: (uri) {
            final connection = libraryEventChannelFactory()(uri);
            return (
              channel: connection.channel.then((connected) async {
                established.complete();
                await release.future;
                return connected;
              }),
              cancel: connection.cancel,
            );
          },
        ),
      );
      channel.start();
      final peer = await server.nextConnection().timeout(const Duration(seconds: 5));
      addTearDown(peer.close);
      await established.future.timeout(const Duration(seconds: 5));
      final peerClosed = peer.done;

      channel.stop();
      release.complete();

      await peerClosed.timeout(const Duration(seconds: 5));
      expect(channel.isRunning, isFalse);
    });
  });
}

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not reached within 5s');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
