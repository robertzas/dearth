import 'dart:convert';

import 'package:dearth_app/core/platform/freekiosk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The FreeKiosk bridge (SPEC §13.9) against FreeKiosk v2.0.0-beta.4's
/// documented responses.
void main() {
  test('§13.9: status, screen off and on go to 127.0.0.1 with the key', () async {
    final seen = <String>[];
    final k = FreeKiosk(
      port: 8080,
      key: 'abcde-12345',
      client: MockClient((req) async {
        seen.add('${req.method} ${req.url}');
        expect(req.headers['X-Api-Key'], 'abcde-12345');
        if (req.url.path == '/api/status') {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'screen': {'on': true, 'brightness': 75, 'screensaverActive': false},
                'device': {'model': 'JT215M', 'manufacturer': 'Joyhong', 'android': '10'},
                'kiosk': {'enabled': true, 'pinEnabled': true},
              },
              'timestamp': 1791580950,
            }),
            200,
          );
        }
        return http.Response('{"success":true,"data":{}}', 200);
      }),
    );
    final s = await k.status();
    expect(s.screenOn, isTrue);
    expect(s.model, 'JT215M');
    expect(s.kiosk, isTrue);
    expect(k.link, FreeKioskLink.ok);
    await k.screenOff();
    await k.screenOn();
    expect(seen, ['GET http://127.0.0.1:8080/api/status', 'POST http://127.0.0.1:8080/api/screen/off', 'POST http://127.0.0.1:8080/api/screen/on']);
  });

  test('§13.9: a key FreeKiosk doesn’t hold, or nothing on the port, says which', () async {
    final wrong = FreeKiosk(
      port: 8080,
      key: 'old',
      client: MockClient((_) async => http.Response('{"success":false,"error":"Invalid or missing API key","timestamp":1791580950}', 401)),
    );
    await expectLater(wrong.screenOff(), throwsA(isA<FreeKioskException>().having((e) => e.link, 'link', FreeKioskLink.unauthorized)));
    expect(wrong.link, FreeKioskLink.unauthorized);

    final none = FreeKiosk(port: 8080, key: 'k', client: MockClient((_) async => throw http.ClientException('Connection refused')));
    await expectLater(none.status(), throwsA(isA<FreeKioskException>().having((e) => e.link, 'link', FreeKioskLink.unreachable)));
  });
}
