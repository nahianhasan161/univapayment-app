import 'package:flutter_test/flutter_test.dart';
import 'package:mfs_merchant_app/sms_analysis.dart';

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
}
