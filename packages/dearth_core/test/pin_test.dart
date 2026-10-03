import 'dart:convert';
import 'dart:math';

import 'package:dearth_core/dearth_core.dart';
import 'package:test/test.dart';

String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('PBKDF2-HMAC-SHA256', () {
    // RFC 7914 §11 test vectors (PBKDF2-HMAC-SHA-256, first 32 bytes).
    test('RFC 7914 vector: passwd/salt, c=1', () {
      expect(
        _hex(pbkdf2Sha256(utf8.encode('passwd'), utf8.encode('salt'), 1)),
        '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc',
      );
    });

    test('RFC 6070-style vector: password/salt, c=2', () {
      expect(
        _hex(pbkdf2Sha256(utf8.encode('password'), utf8.encode('salt'), 2)),
        'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
      );
    });
  });

  group('SPEC §9.1 grown-up PINs', () {
    test('hash then verify accepts the right PIN only', () {
      final stored = hashPin('2468', random: Random(1));
      expect(stored, startsWith('pbkdf2\$$kPinIterations\$'));
      expect(verifyPin('2468', stored), isTrue);
      expect(verifyPin('2469', stored), isFalse);
      expect(verifyPin('', stored), isFalse);
    });

    test('salts differ between hashes of the same PIN', () {
      expect(hashPin('1234'), isNot(hashPin('1234')));
    });

    test('malformed stored values never verify', () {
      for (final bad in [null, '', 'plain', r'pbkdf2$x$y$z', r'pbkdf2$0$AAAA$AAAA', r'md5$1$a$b']) {
        expect(verifyPin('1234', bad), isFalse, reason: '$bad');
      }
    });
  });
}
