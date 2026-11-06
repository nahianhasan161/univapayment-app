import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'format.dart';

const _channel = MethodChannel('univapayment/device');

/// The device token stays in the native layer, so requests go through it.
class MerchantApi {
  const MerchantApi();

  Future<Map<String, dynamic>> get(String path, [Map<String, String> query = const {}]) async {
    final text = await _channel.invokeMethod<String>('api', {
      'method': 'GET',
      'path': Uri(path: path, queryParameters: query.isEmpty ? null : query).toString(),
    });
    return jsonDecode(text!) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> post(String path, Map<String, Object?> body, [Map<String, String> query = const {}]) async {
    final text = await _channel.invokeMethod<String>('api', {
      'method': 'POST',
      'path': Uri(path: path, queryParameters: query.isEmpty ? null : query).toString(),
      'body': jsonEncode(body),
    });
    return jsonDecode(text!) as Map<String, dynamic>;
  }
}

const merchantApi = MerchantApi();

String _errorText(PlatformException e) => switch (e.code) {
      'network' => 'সার্ভারে পৌঁছানো যায়নি। নেট দেখে আবার চেষ্টা করুন।',
      'wrong_status' => 'পেমেন্টটা এর মধ্যেই বদলে গেছে।',
      'rate_limited' => 'অনেকবার চেষ্টা হয়েছে। এক মিনিট পর চেষ্টা করুন।',
      'invalid_token' => 'এই ফোনটা বাতিল করা হয়েছে।',
      _ => 'সমস্যা হয়েছে: ${e.code}',
    };

const _actionLabels = {'approve': 'অনুমোদন', 'reject': 'বাতিল', 'refund': 'ফেরত চিহ্নিত করুন'};
const _actionQuestions = {
  'approve': 'টাকা পেয়েছেন নিশ্চিত হয়ে অনুমোদন করুন। অনুমোদন করলে দোকানের অর্ডার নিশ্চিত হবে।',
  'reject': 'পেমেন্টটা বাতিল হবে, আর কাস্টমার বাতিল দেখবে।',
  'refund': 'এটা শুধু হিসাবে ফেরত চিহ্নিত করে। টাকা আপনাকেই ফেরত পাঠাতে হবে।',
};

/// Asks first, because a mistaken approval confirms an order for money that never came.
Future<bool> runPaymentAction(BuildContext context, Map<String, dynamic> payment, String action) async {
  final sure = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('${taka(payment['amount_poisha'] as num?)}: ${_actionLabels[action]}?'),
      content: Text('${payment['payer_number'] ?? ''}\n\n${_actionQuestions[action]}'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('না')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(_actionLabels[action]!)),
      ],
    ),
  );
  if (sure != true || !context.mounted) return false;
  try {
    await merchantApi.post('/api/v1/device/payments/${payment['id']}/review', {'action': action});
    return true;
  } on PlatformException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_errorText(e))));
    }
    return false;
  }
}

class PaymentCard extends StatelessWidget {
  const PaymentCard({super.key, required this.payment, required this.onChanged});

  final Map<String, dynamic> payment;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final status = payment['status'] as String;
    final reason = reviewReasons[payment['review_reason']];
    final provider = providerNames[payment['provider']];
    final actions = actionsFor(status);
    final details = [
      ?provider,
      ?payment['payer_number'] as String?,
    ].join(' · ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(taka(payment['amount_poisha'] as num?), style: Theme.of(context).textTheme.titleMedium),
                Chip(label: Text(statusLabels[status] ?? status), visualDensity: VisualDensity.compact),
              ],
            ),
            if (details.isNotEmpty) Text(details),
            if (reason != null) Text(reason),
            if (payment['order_id'] != null) Text('অর্ডার: ${payment['order_id']}'),
            if (payment['trx_id'] != null) Text('TrxID: ${payment['trx_id']}'),
            Text(localTime(payment['created_at'] as String?), style: Theme.of(context).textTheme.bodySmall),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final action in actions)
                    action == 'approve'
                        ? FilledButton(
                            onPressed: () => _act(context, action),
                            child: Text(_actionLabels[action]!),
                          )
                        : OutlinedButton(
                            onPressed: () => _act(context, action),
                            child: Text(_actionLabels[action]!),
                          ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _act(BuildContext context, String action) async {
    if (await runPaymentAction(context, payment, action)) onChanged();
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(padding: const EdgeInsets.all(12), child: Text(message)),
      );
}

class OverviewTab extends StatefulWidget {
  const OverviewTab({
    super.key,
    required this.overview,
    required this.error,
    required this.onRefresh,
    required this.onMode,
    required this.onChanged,
  });

  final Map<String, dynamic>? overview;
  final String? error;
  final Future<void> Function() onRefresh;
  final ValueChanged<String> onMode;
  final VoidCallback onChanged;

  @override
  State<OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<OverviewTab> {
  String _period = 'daily';

  @override
  Widget build(BuildContext context) {
    final data = widget.overview;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.error != null) _ErrorCard(widget.error!),
            if (data == null && widget.error == null)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
            if (data != null) ..._content(context, data),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, Map<String, dynamic> data) {
    final totals = data['totals'] as Map<String, dynamic>;
    final review = (data['review'] as List).cast<Map<String, dynamic>>();
    final rows = (totals[_period] as List).cast<Map<String, dynamic>>();
    final titles = Theme.of(context).textTheme;
    return [
      Text(data['merchant_name'] as String, style: titles.titleLarge),
      const SizedBox(height: 12),
      SegmentedButton<String>(
        segments: [
          const ButtonSegment(value: 'test', label: Text('Sandbox')),
          ButtonSegment(value: 'live', label: const Text('Live'), enabled: data['live'] == true),
        ],
        selected: {data['mode'] as String},
        onSelectionChanged: (s) => widget.onMode(s.first),
      ),
      const SizedBox(height: 12),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.6,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        children: [
          _Tile('আজ', totals['today'] as Map<String, dynamic>),
          _Tile('এই মাসে', totals['month'] as Map<String, dynamic>),
          _Tile('এই বছরে', totals['year'] as Map<String, dynamic>),
          _Tile('সব মিলিয়ে', totals['all'] as Map<String, dynamic>),
        ],
      ),
      const Padding(
        padding: EdgeInsets.only(top: 4, bottom: 12),
        child: Text('শুধু সম্পন্ন পেমেন্ট গোনা হয়। ফেরত চিহ্নিত পেমেন্ট বাদ যায়।', style: TextStyle(fontSize: 12)),
      ),
      Text('হাতে যাচাই করুন (${data['review_count']})', style: titles.titleMedium),
      const SizedBox(height: 4),
      if (review.isEmpty)
        const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('এখন হাতে যাচাই করার মতো কোনো পেমেন্ট নেই।'))),
      for (final p in review) PaymentCard(payment: p, onChanged: widget.onChanged),
      const SizedBox(height: 16),
      Text('লেনদেনের হিসাব', style: titles.titleMedium),
      const SizedBox(height: 8),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'daily', label: Text('দৈনিক')),
          ButtonSegment(value: 'monthly', label: Text('মাসিক')),
          ButtonSegment(value: 'yearly', label: Text('বার্ষিক')),
        ],
        selected: {_period},
        onSelectionChanged: (s) => setState(() => _period = s.first),
      ),
      const SizedBox(height: 4),
      if (rows.isEmpty)
        const Padding(padding: EdgeInsets.all(16), child: Text('এই সময়ে কোনো সম্পন্ন পেমেন্ট নেই।')),
      for (final r in rows)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(r['period'] as String),
          subtitle: Text('${r['count']}টা পেমেন্ট'),
          trailing: Text(taka(r['amount_poisha'] as num?), style: titles.titleSmall),
        ),
    ];
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.total);
  final String label;
  final Map<String, dynamic> total;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(taka(total['amount_poisha'] as num?), style: Theme.of(context).textTheme.titleLarge),
              ),
              Text('${total['count']}টা পেমেন্ট', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      );
}

class PaymentsTab extends StatefulWidget {
  const PaymentsTab({super.key, required this.mode, required this.changes, required this.onChanged});

  final String mode;
  final int changes;
  final VoidCallback onChanged;

  @override
  State<PaymentsTab> createState() => _PaymentsTabState();
}

class _PaymentsTabState extends State<PaymentsTab> {
  final _search = TextEditingController();
  final List<Map<String, dynamic>> _rows = [];
  String? _status;
  int _page = 1;
  int _total = 0;
  bool _hasMore = false;
  bool _loading = false;
  String? _error;

  static const _filters = ['review', 'pending', 'completed', 'rejected', 'refunded', 'expired'];

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void didUpdateWidget(PaymentsTab old) {
    super.didUpdateWidget(old);
    if (old.mode != widget.mode || old.changes != widget.changes) _load(reset: true);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({required bool reset}) async {
    final page = reset ? 1 : _page + 1;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await merchantApi.get('/api/v1/device/payments', {
        'mode': widget.mode,
        'page': '$page',
        'status': ?_status,
        if (_search.text.trim().isNotEmpty) 'q': _search.text.trim(),
      });
      if (!mounted) return;
      setState(() {
        if (reset) _rows.clear();
        _rows.addAll((data['payments'] as List).cast<Map<String, dynamic>>());
        _page = page;
        _total = (data['total'] as num).toInt();
        _hasMore = data['has_more'] == true;
      });
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(reset: true),
              decoration: InputDecoration(
                labelText: 'নম্বর, TrxID বা অর্ডার',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'খুঁজুন',
                  icon: const Icon(Icons.search),
                  onPressed: () => _load(reset: true),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _chip('সব', null),
                  for (final s in _filters) _chip(statusLabels[s]!, s),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text('মোট $_totalটা পেমেন্ট', style: Theme.of(context).textTheme.bodySmall),
            if (_error != null) _ErrorCard(_error!),
            for (final p in _rows) PaymentCard(payment: p, onChanged: widget.onChanged),
            if (!_loading && _rows.isEmpty && _error == null)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('কোনো পেমেন্ট পাওয়া যায়নি।'))),
            if (_loading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
            if (_hasMore && !_loading)
              OutlinedButton(onPressed: () => _load(reset: false), child: const Text('আরও দেখুন')),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String? value) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: _status == value,
          onSelected: (_) {
            setState(() => _status = value);
            _load(reset: true);
          },
        ),
      );
}

class NotificationsTab extends StatefulWidget {
  const NotificationsTab({super.key, required this.mode, required this.refresh, required this.onChanged});

  final String mode;
  final int refresh;
  final Future<void> Function() onChanged;

  @override
  State<NotificationsTab> createState() => _NotificationsTabState();
}

class _NotificationsTabState extends State<NotificationsTab> {
  List<Map<String, dynamic>> _rows = const [];
  int _unread = 0;
  bool _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(NotificationsTab old) {
    super.didUpdateWidget(old);
    if (old.mode != widget.mode || old.refresh != widget.refresh) _load();
  }

  Future<void> _load() async {
    try {
      final data = await merchantApi.get('/api/v1/device/notifications', {'mode': widget.mode});
      if (!mounted) return;
      setState(() {
        _rows = (data['notifications'] as List).cast<Map<String, dynamic>>();
        _unread = (data['unread'] as num).toInt();
        _loaded = true;
        _error = null;
      });
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = _errorText(e));
    }
  }

  Future<void> _markRead([String? id]) async {
    try {
      await merchantApi.post('/api/v1/device/notifications/read', {'id': ?id}, {'mode': widget.mode});
      await _load();
      await widget.onChanged();
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = _errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('নোটিফিকেশন', style: Theme.of(context).textTheme.titleLarge),
                if (_unread > 0) TextButton(onPressed: _markRead, child: Text('সব পড়া হয়েছে ($_unread)')),
              ],
            ),
            if (_error != null) _ErrorCard(_error!),
            if (_loaded && _rows.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('এখনো কোনো নোটিফিকেশন নেই।'))),
            for (final n in _rows)
              Card(
                color: n['read_at'] == null ? Theme.of(context).colorScheme.primaryContainer : null,
                child: ListTile(
                  title: Text(n['title'] as String),
                  subtitle: Text([
                    if ((n['body'] as String).isNotEmpty) n['body'] as String,
                    localTime(n['created_at'] as String?),
                  ].join('\n')),
                  onTap: n['read_at'] == null ? () => _markRead(n['id'] as String) : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
