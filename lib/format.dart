/// Display helpers for the merchant screens.
library;

/// 123456789 poisha becomes ৳1,234,567.89.
String taka(num? poisha) {
  if (poisha == null) return '-';
  final total = poisha.round();
  final whole = (total.abs() ~/ 100).toString();
  final fraction = (total.abs() % 100).toString().padLeft(2, '0');
  final grouped = whole.replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');
  return '${total < 0 ? '-' : ''}৳$grouped.$fraction';
}

String localTime(String? iso) {
  final parsed = iso == null ? null : DateTime.tryParse(iso);
  if (parsed == null) return '-';
  final t = parsed.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.day)}/${two(t.month)}/${t.year} ${two(t.hour)}:${two(t.minute)}';
}

const statusLabels = {
  'initiated': 'শুরু হয়েছে',
  'pending': 'অপেক্ষায়',
  'review': 'রিভিউ দরকার',
  'completed': 'সম্পন্ন',
  'rejected': 'বাতিল',
  'expired': 'মেয়াদ শেষ',
  'refunded': 'ফেরত',
};

const reviewReasons = {
  'timeout': '৩ মিনিটে SMS মেলেনি',
  'ambiguous': 'একই নম্বর ও amount-এ একাধিক পেমেন্ট',
  'amount_mismatch': 'টাকার পরিমাণ মেলেনি',
};

const providerNames = {'bkash': 'bKash', 'nagad': 'Nagad'};

/// Which manual actions a payment allows, matching what the server accepts.
List<String> actionsFor(String status) => switch (status) {
      'pending' || 'review' => const ['approve', 'reject'],
      'completed' => const ['refund'],
      _ => const [],
    };
