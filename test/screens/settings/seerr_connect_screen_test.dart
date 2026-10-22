import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/models/seerr/seerr_session.dart';
import 'package:plezy/providers/seerr_account_provider.dart';
import 'package:plezy/screens/settings/seerr_connect_screen.dart';
import 'package:plezy/services/seerr/seerr_auth_service.dart';
import 'package:plezy/services/seerr/seerr_constants.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:provider/provider.dart';

/// Records what the connect flow produced instead of persisting it: the real
/// store writes through the credential vault.
class _RecordingAccount extends SeerrAccountProvider {
  _RecordingAccount(SeerrAuthService authService) : super(authService: authService);

  SeerrSession? adopted;

  @override
  Future<void> adoptSession(SeerrSession session) async => adopted = session;
}

http.Response _json(Object body, {int status = 200, Map<String, String>? headers}) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json', ...?headers});

Map<String, Object?> _publicSettings({bool localLogin = true}) => {
  'initialized': true,
  'applicationTitle': 'Requests',
  'localLogin': localLogin,
  'mediaServerLogin': true,
  'mediaServerType': 4,
};

/// A Seerr that answers only on plain HTTP at its default port — the LAN setup
/// that used to fail because the form assumed https.
SeerrAuthService _plainHttpLanInstance({bool localLogin = true}) {
  return SeerrAuthService(
    httpClientFactory: () => MockClient((request) async {
      if (request.url.scheme != 'http' || request.url.port != SeerrConstants.defaultPort) {
        throw http.ClientException('connection refused', request.url);
      }
      return _json(_publicSettings(localLogin: localLogin));
    }),
  );
}

/// An instance with local sign-in that accepts any email and password.
/// [bodies] records each `/auth/local` request body.
SeerrAuthService _localLoginInstance(List<Object?> bodies) {
  return SeerrAuthService(
    httpClientFactory: () => MockClient((request) async {
      switch (request.url.path) {
        case '/api/v1/settings/public':
          return _json(_publicSettings());
        case '/api/v1/auth/local':
          bodies.add(jsonDecode(request.body));
          return _json(
            {'id': 3, 'displayName': 'Alice', 'permissions': 2},
            headers: {'set-cookie': '${SeerrConstants.sessionCookieName}=fresh; Path=/'},
          );
        case '/api/v1/auth/me':
          // Sign-in reads the user back through /auth/me with the fresh cookie.
          expect(request.headers['Cookie'], '${SeerrConstants.sessionCookieName}=fresh');
          return _json({'id': 3, 'displayName': 'Alice', 'permissions': 2});
      }
      throw http.ClientException('unexpected ${request.url.path}', request.url);
    }),
  );
}

void main() {
  late _RecordingAccount account;

  tearDown(() => account.dispose());

  Widget app(SeerrAuthService auth, {ValueChanged<Future<bool?>>? onRoute}) {
    account = _RecordingAccount(auth);
    return ChangeNotifierProvider<SeerrAccountProvider>.value(
      value: account,
      child: MaterialApp(
        theme: monoTheme(dark: true),
        home: onRoute == null
            ? const SeerrConnectScreen()
            : Builder(
                builder: (context) => TextButton(
                  onPressed: () => onRoute(
                    Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const SeerrConnectScreen())),
                  ),
                  child: const Text('Open route'),
                ),
              ),
      ),
    );
  }

  Future<void> submitUrl(WidgetTester tester, String input) async {
    await tester.enterText(find.byType(TextField).first, input);
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
  }

  testWidgets('a schemeless address reaches a plain-HTTP instance on the default port', (tester) async {
    await tester.pumpWidget(app(_plainHttpLanInstance()));
    await submitUrl(tester, 'seerr.lan');

    // The URL that answered is what the sign-in and the session will use.
    expect(find.text('http://seerr.lan:5055'), findsOneWidget);
    expect(find.text('Requests'), findsOneWidget);
  });

  testWidgets('an unreachable address keeps the URL step with the primary candidate named', (tester) async {
    await tester.pumpWidget(
      app(
        SeerrAuthService(
          httpClientFactory: () =>
              MockClient((request) async => throw http.ClientException('connection refused', request.url)),
        ),
      ),
    );
    await submitUrl(tester, 'seerr.lan');

    expect(find.textContaining('https://seerr.lan'), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);
  });

  testWidgets('signing in with an email adopts a local session and pops', (tester) async {
    final bodies = <Object?>[];
    Future<bool?>? route;
    await tester.pumpWidget(app(_localLoginInstance(bodies), onRoute: (r) => route = r));
    await tester.tap(find.text('Open route'));
    await tester.pumpAndSettle();
    await submitUrl(tester, 'https://seerr.example.com');

    expect(find.text(t.seerr.email), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'alice@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'pw');
    await tester.tap(find.text(t.addServer.signIn));
    await tester.pumpAndSettle();

    expect(bodies, [
      {'email': 'alice@example.com', 'password': 'pw'},
    ]);
    expect(account.adopted?.method, SeerrAuthMethod.local);
    expect(account.adopted?.identifier, 'alice@example.com');
    expect(account.adopted?.instanceLabel, 'Requests');
    expect(await route, isTrue);
  });

  testWidgets('an instance without local sign-in says no method is available', (tester) async {
    await tester.pumpWidget(app(_plainHttpLanInstance(localLogin: false)));
    await submitUrl(tester, 'seerr.lan');

    expect(find.text(t.seerr.noSignInMethods), findsOneWidget);
    expect(find.text(t.addServer.signIn), findsNothing);
  });
}
