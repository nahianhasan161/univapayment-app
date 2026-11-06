import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pair_link.dart';
import 'scan_page.dart';
import 'sms_analysis.dart';

void main() => runApp(const UnivaPaymentApp());

const _channel = MethodChannel('univapayment/device');

/// Set for a real build with --dart-define=API_URL=https://your-domain.
const _defaultServer = String.fromEnvironment(
  'API_URL',
  defaultValue: kDebugMode ? 'http://10.0.2.2:3000' : '',
);

const _brand = Color(0xFF0F766E);

class UnivaPaymentApp extends StatelessWidget {
  const UnivaPaymentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UnivaPayment',
      theme: ThemeData(colorSchemeSeed: _brand, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _code = TextEditingController();
  final _server = TextEditingController(text: _defaultServer);

  Map<Object?, Object?> _status = const {};
  List<Map<Object?, Object?>> _recent = const [];
  SmsReport? _report;
  bool _busy = false;
  String? _error;

  bool get _permitted => _status['permitted'] == true;
  bool get _paired => _status['paired'] == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _code.dispose();
    _server.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final status = await _channel.invokeMapMethod<Object?, Object?>('status') ?? const {};
    final recent = await _channel.invokeListMethod<Map<Object?, Object?>>('recent') ?? const [];
    if (!mounted) return;
    setState(() {
      _status = status;
      _recent = recent;
    });
  }

  Future<void> _run(Future<void> Function() work) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work();
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = _describe(e.code));
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  String _describe(String code) => switch (code) {
        'invalid_code' => 'কোডটা ভুল বা মেয়াদ শেষ। ড্যাশবোর্ড থেকে নতুন কোড নিন।',
        'rate_limited' => 'অনেকবার চেষ্টা হয়েছে। কয়েক মিনিট পর আবার চেষ্টা করুন।',
        'invalid_token' => 'এই ফোনটা বাতিল করা হয়েছে। আবার যুক্ত করুন।',
        'network' => 'সার্ভারে পৌঁছানো যায়নি। নেট ও সার্ভারের ঠিকানা দেখুন।',
        _ => 'সমস্যা হয়েছে: $code',
      };

  Future<void> _pairWith(String url, String code) => _run(() async {
        await _channel.invokeMethod<void>('requestPermissions');
        await _channel.invokeMethod<void>('pair', {'url': url, 'code': code});
        _code.clear();
      });

  /// The code box also accepts the whole link from the QR.
  Future<void> _pairManually() async {
    final entered = _code.text.trim();
    final link = entered.startsWith('univapayment:') ? _parse(entered) : null;
    if (entered.startsWith('univapayment:') && link == null) {
      setState(() => _error = _badQr);
      return;
    }
    await _pairWith(link?.serverUrl ?? _server.text.trim(), link?.code ?? entered);
  }

  static const _badQr = 'এই QR UnivaPayment-এর নয়। ড্যাশবোর্ডের QR স্ক্যান করুন, অথবা কোড দিয়ে যুক্ত করুন।';

  PairLink? _parse(String raw) =>
      parsePairLink(raw, allowHttp: kDebugMode, pinnedServer: _defaultServer);

  Future<void> _scanQr() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScanPage()),
    );
    if (raw == null || !mounted) return;
    final link = _parse(raw);
    if (link == null) {
      setState(() => _error = _badQr);
      return;
    }
    // A QR can come from anyone, so show where the SMS would go.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('এই সার্ভারে যুক্ত করবেন?'),
        content: Text('আপনার bKash ও Nagad SMS এই ঠিকানায় পাঠানো হবে:\n\n${link.host}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('না')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('যুক্ত করুন')),
        ],
      ),
    );
    if (confirmed == true) await _pairWith(link.serverUrl, link.code);
  }

  Future<void> _scan() => _run(() async {
        final rows = await _channel.invokeListMethod<Map<Object?, Object?>>('scanInbox', {'limit': 500}) ?? const [];
        final report = analyze([
          for (final r in rows) (sender: r['sender']! as String, body: r['body']! as String),
        ]);
        if (mounted) setState(() => _report = report);
      });

  Future<void> _copyReport() async {
    await Clipboard.setData(ClipboardData(text: _report!.toShareableText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('মাস্ক করা রিপোর্ট কপি হয়েছে')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset('assets/logo.png', width: 44, height: 44),
                  ),
                  const SizedBox(width: 12),
                  const Text('UnivaPayment', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 20),
              if (_error != null) ...[
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
                ),
                const SizedBox(height: 8),
              ],
              if (_paired) _connected(context) else _pairing(context),
              const SizedBox(height: 24),
              _reportSection(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pairing(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('এই ফোনটা যুক্ত করুন', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text('ড্যাশবোর্ডের "ফোন" পেজে QR তৈরি করে স্ক্যান করুন। অ্যাপ শুধু bKash ও Nagad-এর SMS, আর Sandbox-এর টেস্ট SMS পড়ে।'),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('scan'),
              onPressed: _busy ? null : _scanQr,
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(_busy ? 'যুক্ত হচ্ছে…' : 'QR স্ক্যান করুন'),
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              key: const Key('manual'),
              tilePadding: EdgeInsets.zero,
              title: const Text('কোড দিয়ে যুক্ত করুন'),
              subtitle: const Text('QR কাজ না করলে'),
              childrenPadding: const EdgeInsets.only(bottom: 4),
              children: [
                TextField(
                  key: const Key('code'),
                  controller: _code,
                  decoration: const InputDecoration(labelText: 'পেয়ারিং কোড', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('server'),
                  controller: _server,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(labelText: 'সার্ভারের ঠিকানা', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _busy ? null : _pairManually,
                    child: const Text('যুক্ত করুন'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _connected(BuildContext context) {
    final revoked = _status['revoked'] == true;
    final lastError = _status['lastError'] as String?;
    final lastSync = _status['lastSyncAt'] as int? ?? 0;
    final healthy = !revoked && lastError == null && _permitted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(healthy ? Icons.check_circle : Icons.error, color: healthy ? _brand : Colors.orange),
                    const SizedBox(width: 8),
                    Text(
                      revoked
                          ? 'ফোনটা বাতিল করা হয়েছে'
                          : !_permitted
                              ? 'SMS অনুমতি দরকার'
                              : lastError != null
                                  ? 'সার্ভারে পাঠানো যাচ্ছে না'
                                  : 'যুক্ত আছে, স্বয়ংক্রিয় চলছে',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('সার্ভারে পাঠানো: ${_status['sent'] ?? 0}টা SMS'),
                Text('পাঠানোর অপেক্ষায়: ${_status['unsent'] ?? 0}টা SMS'),
                Text('শেষ যোগাযোগ: ${lastSync == 0 ? '-' : _time(lastSync)}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (!_permitted)
          FilledButton(
            onPressed: () => _run(() async => _channel.invokeMethod<void>('requestPermissions')),
            child: const Text('SMS পড়ার অনুমতি দিন'),
          ),
        if (revoked)
          FilledButton(
            onPressed: () => _run(() async => _channel.invokeMethod<void>('unpair')),
            child: const Text('আবার যুক্ত করুন'),
          )
        else
          OutlinedButton(
            onPressed: _busy ? null : () => _run(() async => _channel.invokeMethod<void>('syncNow')),
            child: const Text('এখনই পাঠান'),
          ),
        OutlinedButton(
          onPressed: () => _channel.invokeMethod<void>('openBatterySettings'),
          child: const Text('ব্যাটারি সেটিংস খুলুন'),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'অ্যাপকে battery optimization থেকে বাদ দিন, আর Force stop করবেন না। নইলে SMS দেরিতে পৌঁছাতে পারে।',
            style: TextStyle(fontSize: 13),
          ),
        ),
        if (_recent.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('সর্বশেষ SMS', style: Theme.of(context).textTheme.titleMedium),
          for (final r in _recent)
            Card(
              child: ListTile(
                title: Text('${r['sender']} · ${r['sentAt'] == null ? 'অপেক্ষায়' : 'পাঠানো হয়েছে'}'),
                subtitle: Text(maskSms(r['body']! as String)),
              ),
            ),
        ],
      ],
    );
  }

  Widget _reportSection(BuildContext context) {
    final report = _report;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('SMS ফরম্যাট রিপোর্ট', style: Theme.of(context).textTheme.titleMedium),
        const Text('পুরোনো SMS-এর ফরম্যাট দেখে মাস্ক করা রিপোর্ট বানায়। আপনি কপি না করলে এটা ফোনের বাইরে যায় না।'),
        const SizedBox(height: 8),
        if (!_permitted)
          OutlinedButton(
            onPressed: () => _run(() async => _channel.invokeMethod<void>('requestPermissions')),
            child: const Text('SMS পড়ার অনুমতি দিন'),
          )
        else
          OutlinedButton(
            onPressed: _busy ? null : _scan,
            child: const Text('পুরোনো SMS পরীক্ষা করুন'),
          ),
        if (report != null) ...[
          const SizedBox(height: 12),
          Text('মোট: ${report.total}টা SMS'),
          Text('টাকা আসার SMS-এ পুরো নম্বর: ${report.incomingWith(NumberVisibility.full)}'),
          Text('টাকা আসার SMS-এ আংশিক নম্বর: ${report.incomingWith(NumberVisibility.partial)}'),
          Text('টাকা আসার SMS-এ নম্বর নেই: ${report.incomingWith(NumberVisibility.none)}'),
          const SizedBox(height: 8),
          FilledButton.tonal(onPressed: _copyReport, child: const Text('মাস্ক করা রিপোর্ট কপি করুন')),
          for (final t in report.templates)
            Card(
              child: ListTile(
                title: Text('${t.sender} ×${t.count} · নম্বর: ${t.visibility.name}'),
                subtitle: Text(t.sample),
              ),
            ),
        ],
      ],
    );
  }

  String _time(int millis) {
    final t = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
  }
}
