import 'package:flutter_test/flutter_test.dart';
import 'package:univapayment_app/pair_link.dart';
import 'package:univapayment_app/sms_analysis.dart';

// Made-up values; only the shape of the message matters here.
const incoming =
    'You have received Tk 500.00 from 01712345678. Fee Tk 0.00. '
    'Balance Tk 1,500.00. TrxID ABC123XYZ9 at 06/11/2026 10:30';

void main() {
  test('finds a full, partial or missing sender number', () {
    expect(numberVisibility(incoming), NumberVisibility.full);
    expect(numberVisibility('from 017***5678'), NumberVisibility.partial);
    expect(numberVisibility('Your OTP is 1234'), NumberVisibility.none);
  });

  test('a full number needs exactly 11 digits', () {
    expect(numberVisibility('id 9901712345678'), NumberVisibility.none);
    expect(numberVisibility('from 8801712345678.'), NumberVisibility.full);
  });

  test('masking removes personal values but keeps the format', () {
    final masked = maskSms(incoming);
    expect(masked, isNot(contains('01712345678')));
    expect(masked, isNot(contains('ABC123XYZ9')));
    expect(masked, isNot(contains('1,500')));
    expect(masked, contains('from ###########.'));
    expect(masked, contains('TrxID [TRX] at'));
  });

  test('reference text is hidden', () {
    final masked = maskSms('from 01712345678. Ref Rahim Uddin. Fee Tk 0.00');
    expect(masked, isNot(contains('Rahim')));
    expect(masked, contains('Ref [REF].'));
  });

  test('messages with different values share one template', () {
    final report = analyze([
      (sender: 'bKash', body: incoming),
      (
        sender: 'bKash',
        body: incoming
            .replaceAll('500.00', '75.50')
            .replaceAll('01712345678', '01899999999'),
      ),
    ]);
    expect(report.templates, hasLength(1));
    expect(report.incomingWith(NumberVisibility.full), 2);
  });

  test('the shareable report holds no raw values', () {
    final text = analyze([(sender: 'bKash', body: incoming)]).toShareableText();
    expect(text, isNot(contains('01712345678')));
    expect(text, isNot(contains('ABC123XYZ9')));
  });

  group('pairing QR', () {
    const good = 'univapayment://pair?url=https%3A%2F%2Fpay.example.com&code=abc';

    PairLink? parse(String raw, {bool allowHttp = false, String pinned = ''}) =>
        parsePairLink(raw, allowHttp: allowHttp, pinnedServer: pinned);

    test('reads a valid link', () {
      final link = parse(good)!;
      expect(link.serverUrl, 'https://pay.example.com');
      expect(link.code, 'abc');
      expect(link.host, 'pay.example.com');
    });

    test('rejects other QR codes', () {
      expect(parse('https://example.com'), isNull);
      expect(parse('hello'), isNull);
      expect(parse('univapayment://other?url=https%3A%2F%2Fa.test&code=x'), isNull);
      expect(parse('univapayment://pair?url=https%3A%2F%2Fa.test'), isNull);
      expect(parse('univapayment://pair?code=x'), isNull);
    });

    test('allows http only in debug builds', () {
      const http = 'univapayment://pair?url=http%3A%2F%2F10.0.2.2%3A3000&code=x';
      expect(parse(http), isNull);
      expect(parse(http, allowHttp: true), isNotNull);
    });

    test('rejects a server with a hidden login', () {
      expect(parse('univapayment://pair?url=https%3A%2F%2Fgood.test%40evil.test&code=x'), isNull);
    });

    test('a build pinned to one server refuses another', () {
      expect(parse(good, pinned: 'https://pay.example.com'), isNotNull);
      expect(parse(good, pinned: 'https://other.example.com'), isNull);
    });
  });
}
