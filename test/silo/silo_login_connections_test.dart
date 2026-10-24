import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/silo/silo_device_sign_in.dart';
import 'package:plezy/silo/silo_session.dart';
import 'package:plezy/silo/silo_sign_in.dart';

import 'fake_silo.dart';

void main() {
  test('the device code reuses the connections the identity read opened (NetworkModule.kt:17)', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final connections = <String, int>{};
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      connections[request.uri.path] = request.connectionInfo!.remotePort;
      final (int status, Object body) = switch (request.uri.path) {
        '/api/v2/system/identity' => (200, {'server_id': 'srv'}),
        '/api/v2/theme/branding' => (200, {'server_name': 'Home'}),
        '/api/v2/auth/device/capability' => (200, {'state': 'available', 'cancel': true}),
        '/api/v2/auth/device/start' => (
          201,
          {'device_code': 'device-secret', 'user_code': '12345678', 'expires_in': 600, 'interval': 5},
        ),
        '/api/v2/auth/device/poll' => (200, {'status': 'pending'}),
        _ => (200, <String, Object>{}),
      };
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body));
      await request.response.close();
    });
    final session = await SiloSessionController.load(MemorySiloSessionStore());
    final login = SiloLoginController(
      origin: Uri.parse('http://127.0.0.1:${server.port}'),
      device: siloTestDevice,
      sessionFor: (_) async => session,
      deviceName: 'Plezy Test',
      cleartextApproved: (_) => true,
      wait: (_) => Future<void>.delayed(const Duration(days: 1)),
    );
    addTearDown(login.dispose);

    await login.open();
    while ((login.phase as SiloLoginRacing).device is! SiloDeviceShowingCode) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    final opened = {connections['/api/v2/system/identity'], connections['/api/v2/theme/branding']};
    expect(opened, contains(connections['/api/v2/auth/device/capability']));
    expect(opened, contains(connections['/api/v2/auth/device/start']));
  });
}
