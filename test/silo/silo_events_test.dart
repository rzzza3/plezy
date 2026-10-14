import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/library_change_event.dart';
import 'package:plezy/silo/silo_events.dart';
import 'package:plezy/silo/silo_session.dart';

import 'fake_silo.dart';

class _Upgrade {
  final Uri uri;
  final String? authorization;
  final String? profileId;
  final String? profileToken;
  final String? protocols;

  _Upgrade(HttpRequest request)
    : uri = request.uri,
      authorization = request.headers.value('authorization'),
      profileId = request.headers.value('x-profile-id'),
      profileToken = request.headers.value('x-profile-token'),
      protocols = request.headers.value('sec-websocket-protocol');
}

/// A loopback events endpoint that accepts `silo.events.v2` upgrades.
class _EventsServer {
  late final HttpServer _server;
  final List<_Upgrade> upgrades = [];
  final List<WebSocket> sockets = [];
  final List<String> received = [];
  final List<Completer<void>> closed = [];
  final _connected = StreamController<void>.broadcast();

  Stream<void> get connected => _connected.stream;

  void send(String frame) => sockets.last.add(frame);

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) async {
      upgrades.add(_Upgrade(request));
      final socket = await WebSocketTransformer.upgrade(request, protocolSelector: (_) => siloEventsProtocol);
      final done = Completer<void>();
      sockets.add(socket);
      closed.add(done);
      socket.listen((message) => received.add(message as String), onDone: done.complete);
      _connected.add(null);
    });
  }

  SiloSocketConnect connect(List<List<String>> attempts) => (uri, protocols) {
    attempts.add(protocols);
    return connectSiloSocket(uri.replace(scheme: 'ws', host: '127.0.0.1', port: _server.port), protocols);
  };

  Future<void> close() async {
    for (final socket in sockets) {
      await socket.close();
    }
    await _server.close(force: true);
    await _connected.close();
  }
}

String _frame(Map<String, Object?> json) => jsonEncode(json);

String _userState(String profileId, {String change = 'watched'}) => _frame({
  'type': 'event',
  'channel': 'user_state',
  'event': 'user_state.changed',
  'data': {'profile_id': profileId, 'content_id': 'c-1', 'change': change},
});

final String _subscribed = _frame({
  'type': 'subscribed',
  'channels': ['user_state', 'catalog'],
  'rejected': <Object>[],
});

/// Issues `T1`, `T2`, ... so each attempt's ticket is distinguishable.
FakeSilo _ticketServer() {
  var issued = 0;
  return FakeSilo((request) {
    if (request.url.path != '/api/v2/events/ws-ticket') return jsonResponse({}, 404);
    issued++;
    return jsonResponse({
      'ticket': 'T$issued',
      'protocol': 'silo.events.v2',
      'expires_in': 30,
      'max_connection_seconds': 300,
    }, 200);
  });
}

Future<SiloSessionController> _profileSession() async {
  final (session, _) = await signedInSession();
  await session.selectProfile('p-1', 'profile-token-p-1');
  return session;
}

Future<void> _until(bool Function() condition, {Duration timeout = const Duration(seconds: 5)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException('condition not met', timeout);
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  group('frames (HomeRealtimeClient.kt:76-101)', () {
    test('subscribed carries its channels and rejections', () {
      final frame = parseSiloEventFrame(
        _frame({
          'type': 'subscribed',
          'channels': ['user_state'],
          'rejected': [
            {'channel': 'catalog', 'code': 'forbidden', 'message': 'no'},
          ],
        }),
      );

      expect(frame, isA<SiloSubscribed>());
      expect((frame! as SiloSubscribed).channels, ['user_state']);
      expect((frame as SiloSubscribed).rejected, ['catalog']);
    });

    test('user_state.changed decodes its payload (HomeRealtimeClient.kt:14-22)', () {
      final frame = parseSiloEventFrame(_userState('p-9', change: 'home_dismissal')) as SiloUserStateChanged;

      expect(frame.profileId, 'p-9');
      expect(frame.contentId, 'c-1');
      expect(frame.seriesId, isNull);
      expect(frame.change, 'home_dismissal');
    });

    test('any catalog event is a catalog change', () {
      expect(
        parseSiloEventFrame(_frame({'type': 'event', 'channel': 'catalog', 'event': 'catalog.anything'})),
        isA<SiloCatalogChanged>(),
      );
    });

    test('hello, snapshots, errors, foreign channels, other events and junk are dropped', () {
      for (final raw in [
        _frame({'type': 'hello', 'connection_id': 'x'}),
        _frame({'type': 'snapshot', 'channel': 'user_state', 'data': null}),
        _frame({'type': 'error', 'code': 'bad'}),
        _frame({'type': 'event', 'channel': 'notifications', 'event': 'notification.created'}),
        _frame({'type': 'event', 'channel': 'user_state', 'event': 'user_state.other', 'data': <String, Object>{}}),
        _frame({
          'type': 'event',
          'channel': 'user_state',
          'event': 'user_state.changed',
          'data': {'change': 'watched'},
        }),
        '{not json',
        '[1,2]',
      ]) {
        expect(parseSiloEventFrame(raw), isNull, reason: raw);
      }
      expect(parseSiloEventFrame(const [1, 2, 3]), isNull, reason: 'a binary frame');
    });
  });

  test('refetch triggers follow homeRefreshTrigger (HomeRealtimeClient.kt:108-114)', () {
    const mine = SiloUserStateChanged(profileId: 'p-1', change: 'watched');
    const theirs = SiloUserStateChanged(profileId: 'p-2', change: 'watched');

    expect(siloHomeRefreshTrigger(const SiloSubscribed(), 'p-1'), isTrue);
    expect(siloHomeRefreshTrigger(const SiloCatalogChanged(), 'p-1'), isTrue);
    expect(siloHomeRefreshTrigger(mine, 'p-1'), isTrue);
    expect(siloHomeRefreshTrigger(theirs, 'p-1'), isFalse);
    expect(siloHomeRefreshTrigger(theirs, null), isTrue, reason: 'an unknown active profile refreshes');
  });

  group('ticket (EventsSocketV2Api.kt:78-80)', () {
    Map<String, Object?> ticket({
      Object? value = 'abc_DEF-123',
      Object? protocol = 'silo.events.v2',
      Object? expiresIn = 30,
      Object? maxConnection = 300,
    }) => {'ticket': value, 'protocol': protocol, 'expires_in': expiresIn, 'max_connection_seconds': maxConnection};

    test('a valid ticket becomes the two subprotocols and never prints', () {
      final parsed = SiloWsTicket.parse(ticket())!;

      expect(parsed.protocols, ['silo.events.v2', 'silo.ticket.abc_DEF-123']);
      expect(parsed.expiresIn, const Duration(seconds: 30));
      expect(parsed.maxConnection, const Duration(seconds: 300));
      expect('$parsed', isNot(contains('abc_DEF-123')));
    });

    test('a wrong protocol, bounds or token characters are refused', () {
      for (final json in [
        ticket(protocol: 'silo.events.v1'),
        ticket(expiresIn: 0),
        ticket(expiresIn: 31),
        ticket(maxConnection: 0),
        ticket(maxConnection: 301),
        ticket(value: ''),
        ticket(value: 'has space'),
        ticket(value: 'comma,split'),
        ticket(value: 'ünicode'),
        ticket(value: 7),
      ]) {
        expect(SiloWsTicket.parse(json), isNull, reason: '$json');
      }
    });
  });

  test('the socket url is ws(s) on the origin with the channels only (EventsSocketV2Api.kt:82-92)', () {
    expect(
      '${siloEventsUri(Uri.parse('https://silo.ruleone.xyz/some/path?x=1'))}',
      'wss://silo.ruleone.xyz/api/v2/events/ws?channels=user_state%2Ccatalog',
    );
    expect(
      '${siloEventsUri(Uri.parse('http://10.0.0.2:8096'))}',
      'ws://10.0.0.2:8096/api/v2/events/ws?channels=user_state%2Ccatalog',
    );
  });

  group('socket', () {
    late _EventsServer server;
    late FakeSilo tickets;
    late SiloSessionController session;
    late List<List<String>> attempts;
    late List<Duration> waits;
    late List<LibraryChangeEvent> refetches;
    late int staleCalls;
    late SiloEvents events;

    SiloEvents build({Duration debounce = const Duration(milliseconds: 200)}) {
      final built = SiloEvents(
        http: siloHttpFor(tickets, session),
        serverId: ServerId('server-1'),
        onHomeStale: () => staleCalls++,
        connect: server.connect(attempts),
        wait: (delay) async {
          waits.add(delay);
          await Future<void>.delayed(const Duration(milliseconds: 10));
        },
        debounce: debounce,
      );
      built.events.listen(refetches.add);
      addTearDown(built.dispose);
      return built;
    }

    setUp(() async {
      server = _EventsServer();
      await server.start();
      tickets = _ticketServer();
      session = await _profileSession();
      attempts = [];
      waits = [];
      refetches = [];
      staleCalls = 0;
    });

    tearDown(() => server.close());

    test('fetches a ticket with the bearer, upgrades with only the subprotocols, then subscribes first '
        '(EventsSocketV2Api.kt:24-35,63,93-97)', () async {
      events = build();
      events.start();
      await server.connected.first;
      await _until(() => server.received.isNotEmpty);

      final ticketCall = tickets.to('/api/v2/events/ws-ticket').single;
      expect(ticketCall.method, 'POST');
      expect(ticketCall.header('authorization'), 'Bearer access-A');
      final upgrade = server.upgrades.single;
      expect('${upgrade.uri}', '/api/v2/events/ws?channels=user_state%2Ccatalog');
      expect(upgrade.protocols, 'silo.events.v2, silo.ticket.T1');
      expect(upgrade.authorization, isNull);
      expect(upgrade.profileId, isNull);
      expect(upgrade.profileToken, isNull);
      expect(jsonDecode(server.received.first), {
        'type': 'subscribe',
        'channels': ['user_state', 'catalog'],
      });
      expect(events.phase, SiloEventsPhase.connecting);

      server.send(_subscribed);
      await _until(() => events.phase == SiloEventsPhase.subscribed);
      await _until(() => refetches.isNotEmpty);
      expect(refetches.single.homeChanged, isTrue, reason: 'subscribed is the catch-up refetch');
      expect(refetches.single.hasChanges, isFalse, reason: 'a home refetch does not reload library views');
      expect(staleCalls, 1);
    });

    test('five events within 2 s cause one refetch (HomeRealtimeCoordinator.kt:36,63)', () async {
      events = build(debounce: const Duration(seconds: 2));
      events.start();
      await server.connected.first;
      server.send(_subscribed);
      for (var i = 0; i < 3; i++) {
        server.send(_userState('p-1'));
      }
      server.send(_frame({'type': 'event', 'channel': 'catalog', 'event': 'catalog.changed'}));
      await _until(() => events.phase == SiloEventsPhase.subscribed);

      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(refetches, isEmpty, reason: 'the 2 s trailing window is still open');
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(refetches, hasLength(1));
      expect(refetches.single.itemsUpdated, isTrue, reason: 'a catalog event in the window reloads library views');
      expect(staleCalls, 1);
    });

    test('a user_state.changed for another profile causes no refetch (HomeRealtimeClient.kt:111-112)', () async {
      events = build();
      events.start();
      await server.connected.first;
      server.send(_subscribed);
      await _until(() => refetches.length == 1);

      server.send(_userState('p-2'));
      server.send(_userState('p-2', change: 'progress'));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(refetches, hasLength(1));

      server.send(_userState('p-1'));
      await _until(() => refetches.length == 2);
    });

    test(
      'failed attempts back off 1 s doubling to 30 s, each with a fresh ticket (HomeRealtimeCoordinator.kt:57-58)',
      () async {
        events = SiloEvents(
          http: siloHttpFor(tickets, session),
          serverId: ServerId('server-1'),
          connect: (uri, protocols) {
            attempts.add(protocols);
            return (channel: Future.error(const SocketException('refused')), cancel: () {});
          },
          wait: (delay) async {
            waits.add(delay);
            if (waits.length == 7) events.stop();
          },
        );
        addTearDown(events.dispose);
        events.start();
        await _until(() => events.phase == SiloEventsPhase.idle && waits.length == 7);

        expect(waits.map((d) => d.inSeconds), [1, 2, 4, 8, 16, 30, 30]);
        expect(attempts.map((p) => p.last), [for (var i = 1; i <= 7; i++) 'silo.ticket.T$i']);
        expect(tickets.to('/api/v2/events/ws-ticket'), hasLength(7));
      },
    );

    test('a ticket is never reused, even when the upgrade fails (EventsSocketV2Api.kt:46-48)', () async {
      var failNext = true;
      final connect = server.connect(attempts);
      events = SiloEvents(
        http: siloHttpFor(tickets, session),
        serverId: ServerId('server-1'),
        connect: (uri, protocols) {
          if (failNext) {
            failNext = false;
            attempts.add(protocols);
            return (channel: Future.error(const WebSocketException('lost handshake')), cancel: () {});
          }
          return connect(uri, protocols);
        },
        wait: (delay) async => waits.add(delay),
      );
      addTearDown(events.dispose);
      events.start();
      await server.connected.first;

      expect(attempts.map((p) => p.last), ['silo.ticket.T1', 'silo.ticket.T2']);
      expect(server.upgrades.single.protocols, 'silo.events.v2, silo.ticket.T2');
    });

    test('backoff resets to 1 s once a frame arrives (HomeRealtimeCoordinator.kt:44-47)', () async {
      var failures = 2;
      final connect = server.connect(attempts);
      events = SiloEvents(
        http: siloHttpFor(tickets, session),
        serverId: ServerId('server-1'),
        connect: (uri, protocols) {
          if (failures-- > 0) return (channel: Future.error(const SocketException('refused')), cancel: () {});
          return connect(uri, protocols);
        },
        wait: (delay) async {
          waits.add(delay);
          if (waits.length == 3) events.stop();
        },
      );
      addTearDown(events.dispose);
      events.start();
      await server.connected.first;
      server.send(_subscribed);
      await _until(() => events.phase == SiloEventsPhase.subscribed);
      await server.sockets.last.close();
      await _until(() => waits.length == 3);

      expect(waits.map((d) => d.inSeconds), [1, 2, 1]);
    });

    test('sign-out closes the socket and mints no ticket without a session (EventsSocketV2Api.kt:38,53-61)', () async {
      events = build();
      events.start();
      await server.connected.first;
      server.send(_subscribed);
      await _until(() => events.phase == SiloEventsPhase.subscribed);

      await session.signOut();
      await server.closed.single.future.timeout(const Duration(seconds: 3));
      await _until(() => events.phase == SiloEventsPhase.fetchingTicket || events.phase == SiloEventsPhase.backingOff);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(tickets.to('/api/v2/events/ws-ticket'), hasLength(1));
      expect(server.upgrades, hasLength(1));
    });

    test(
      'a profile switch closes the socket and reconnects with a new ticket (HomeRealtimeForegroundStarter.kt:62-64)',
      () async {
        events = build();
        events.start();
        await server.connected.first;
        server.send(_subscribed);
        await _until(() => events.phase == SiloEventsPhase.subscribed);

        final second = server.connected.first;
        await session.selectProfile('p-2', null);
        await server.closed.first.future.timeout(const Duration(seconds: 3));
        await second;

        expect(server.upgrades.map((u) => u.protocols), [
          'silo.events.v2, silo.ticket.T1',
          'silo.events.v2, silo.ticket.T2',
        ]);
        expect(tickets.to('/api/v2/events/ws-ticket').last.header('x-profile-id'), 'p-2');
      },
    );

    test(
      'stop closes the socket and start resumes with a fresh ticket (HomeRealtimeForegroundStarter.kt:34-55)',
      () async {
        events = build();
        events.start();
        await server.connected.first;
        server.send(_subscribed);
        await _until(() => refetches.isNotEmpty);

        events.stop();
        expect(events.phase, SiloEventsPhase.idle);
        await server.closed.single.future.timeout(const Duration(seconds: 3));

        events.start();
        await server.connected.first;
        expect(server.upgrades.last.protocols, 'silo.events.v2, silo.ticket.T2');
      },
    );

    test('stop drops a pending refetch', () async {
      events = build();
      events.start();
      await server.connected.first;
      server.send(_subscribed);
      await _until(() => events.phase == SiloEventsPhase.subscribed);

      events.stop();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(refetches, isEmpty);
    });
  });
}
