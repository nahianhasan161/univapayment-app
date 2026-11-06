/// Pure helpers for the SMS probe. Nothing here touches the network.
library;

enum NumberVisibility { full, partial, none }

final _fullNumber = RegExp(r'(?<!\d)(?:\+?88)?01\d{9}(?!\d)');
final _partialNumber = RegExp(r'\d{2,}[*xX]{2,}\d{2,}|[*xX]{3,}\d{2,}');
final _incoming = RegExp(r'received|cash in', caseSensitive: false);
final _reference = RegExp(r'(Ref(?:erence)?[:\-]?\s*)[^.\n]*', caseSensitive: false);
final _trxId = RegExp(r'((?:TrxID|TxnID)\s*:?\s*)[A-Za-z0-9]+', caseSensitive: false);
final _mixedCode = RegExp(
  r'\b(?=[A-Za-z0-9]*\d)(?=[A-Za-z0-9]*[A-Za-z])[A-Za-z0-9]{6,}\b',
);

NumberVisibility numberVisibility(String body) {
  if (_fullNumber.hasMatch(body)) return NumberVisibility.full;
  if (_partialNumber.hasMatch(body)) return NumberVisibility.partial;
  return NumberVisibility.none;
}

bool looksIncoming(String body) => _incoming.hasMatch(body);

/// Hides personal values but keeps the SMS format and each digit's position.
String maskSms(String body) => body
    .replaceAllMapped(_reference, (m) => '${m[1]}[REF]')
    .replaceAllMapped(_trxId, (m) => '${m[1]}[TRX]')
    .replaceAll(_mixedCode, '[CODE]')
    .replaceAll(RegExp(r'\d'), '#');

/// SMS that differ only in their values fall into the same template.
String templateKey(String body) =>
    maskSms(body).replaceAll(RegExp(r'#[#,.]*'), '#');

class SmsTemplate {
  SmsTemplate(this.sender, this.sample, this.visibility, this.incoming);

  final String sender;
  final String sample;
  final NumberVisibility visibility;
  final bool incoming;
  int count = 0;
}

class SmsReport {
  SmsReport(this.total, this.templates);

  final int total;
  final List<SmsTemplate> templates;

  int incomingWith(NumberVisibility visibility) => templates
      .where((t) => t.incoming && t.visibility == visibility)
      .fold(0, (sum, t) => sum + t.count);

  /// Safe to share: holds only masked samples and counts.
  String toShareableText() {
    final lines = <String>[
      'SMS Probe report',
      'Total: $total',
      'Incoming, full number: ${incomingWith(NumberVisibility.full)}',
      'Incoming, partial number: ${incomingWith(NumberVisibility.partial)}',
      'Incoming, no number: ${incomingWith(NumberVisibility.none)}',
    ];
    for (final t in templates) {
      lines
        ..add('')
        ..add(
          '[${t.sender}] x${t.count} | '
          '${t.incoming ? 'incoming' : 'other'} | number: ${t.visibility.name}',
        )
        ..add(t.sample);
    }
    return lines.join('\n');
  }
}

SmsReport analyze(List<({String sender, String body})> messages) {
  final groups = <String, SmsTemplate>{};
  for (final m in messages) {
    final key = '${m.sender.toLowerCase()}|${templateKey(m.body)}';
    final template = groups.putIfAbsent(
      key,
      () => SmsTemplate(
        m.sender,
        maskSms(m.body),
        numberVisibility(m.body),
        looksIncoming(m.body),
      ),
    );
    template.count++;
  }
  final templates = groups.values.toList()
    ..sort((a, b) => b.count.compareTo(a.count));
  return SmsReport(messages.length, templates);
}
