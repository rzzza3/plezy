import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/exceptions/media_server_exceptions.dart';
import 'package:plezy/profiles/profile.dart';
import 'package:plezy/profiles/profile_activation.dart';
import 'package:plezy/silo/silo_catalog.dart';

import 'fake_silo.dart';

const _kids = Profile(serverId: 'silo-srv', siloProfileId: 'p-2', displayName: 'Kids', hasPin: true);
const _alice = Profile(serverId: 'silo-srv', siloProfileId: 'p-1', displayName: 'Alice');

/// `verify-pin` answers `valid: true` for 1234 only.
http.Response _verifyPin(RecordedRequest request) {
  final pin = (jsonDecode(request.body) as Map)['pin'];
  return pin == '1234'
      ? jsonResponse({'valid': true, 'profile_token': 'profile-token-p-2'}, 200)
      : jsonResponse({'valid': false}, 200);
}

void main() {
  group('switching to a Silo profile', () {
    test('a PIN profile calls verify-pin and enters only on valid: true', () async {
      final (session, _) = await signedInSession();
      final fake = FakeSilo(_verifyPin);
      final pins = ['0000', '1234'];
      final prompts = <String?>[];
      final profileAtPrompt = <String?>[];

      final outcome = await enterSiloProfile(
        http: siloHttpFor(fake, session),
        profile: _kids,
        promptPin: (errorMessage) async {
          prompts.add(errorMessage);
          profileAtPrompt.add(session.session!.profileId);
          return pins.removeAt(0);
        },
      );

      expect(outcome, SiloProfileEntryOutcome.entered);
      final verifies = fake.to('/api/v2/profiles/p-2/verify-pin');
      expect(verifies.map((r) => (jsonDecode(r.body) as Map)['pin']), ['0000', '1234']);
      expect(prompts, [null, t.profiles.incorrectPinTryAgain], reason: 'the retry says the PIN was wrong');
      expect(profileAtPrompt, [null, null], reason: 'valid: false enters nothing');
      expect(session.session!.profileId, 'p-2');
      expect(session.generation, 2, reason: 'one identity change, on the valid PIN');
    });

    test('cancelling the PIN prompt enters nothing', () async {
      final (session, _) = await signedInSession();
      final fake = FakeSilo(_verifyPin);

      final outcome = await enterSiloProfile(
        http: siloHttpFor(fake, session),
        profile: _kids,
        promptPin: (_) async => null,
      );

      expect(outcome, SiloProfileEntryOutcome.cancelled);
      expect(fake.requests, isEmpty);
      expect(session.session!.profileId, isNull);
      expect(session.generation, 1);
    });

    test('a profile without a PIN is entered without verify-pin or a prompt', () async {
      final (session, _) = await signedInSession();
      final fake = FakeSilo(_verifyPin);

      final outcome = await enterSiloProfile(
        http: siloHttpFor(fake, session),
        profile: _alice,
        promptPin: (_) async => fail('no PIN is asked for'),
      );

      expect(outcome, SiloProfileEntryOutcome.entered);
      expect(fake.requests, isEmpty);
      expect(session.session!.profileId, 'p-1');
    });

    test('a home read in flight across the switch is dropped', () async {
      final (session, _) = await signedInSession();
      final homeStarted = Completer<void>();
      final releaseHome = Completer<void>();
      final fake = FakeSilo((request) async {
        if (request.url.path == '/api/v2/home/sections') {
          homeStarted.complete();
          await releaseHome.future;
          return http.Response(File('test/silo/fixtures/home_sections.json').readAsStringSync(), 200);
        }
        return _verifyPin(request);
      });
      final siloHttp = siloHttpFor(fake, session);

      final home = SiloCatalog(siloHttp).homeSections();
      await homeStarted.future;
      final outcome = await enterSiloProfile(http: siloHttp, profile: _kids, promptPin: (_) async => '1234');
      releaseHome.complete();

      expect(outcome, SiloProfileEntryOutcome.entered);
      await expectLater(
        home,
        throwsA(isA<MediaServerHttpException>().having((e) => e.type, 'type', MediaServerHttpErrorType.cancelled)),
        reason: "the previous profile's home must not reach the new one",
      );
    });
  });
}
