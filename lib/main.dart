import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'sms_analysis.dart';

void main() => runApp(const SmsProbeApp());

const _channel = MethodChannel('sms_probe');

class SmsProbeApp extends StatelessWidget {
  const SmsProbeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SMS Probe',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const ProbePage(),
    );
  }
}

class ProbePage extends StatefulWidget {
  const ProbePage({super.key});

  @override
  State<ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<ProbePage> with WidgetsBindingObserver {
  bool _permitted = false;
  bool _scanning = false;
  SmsReport? _report;
  List<Map<Object?, Object?>> _captured = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final permitted = await _channel.invokeMethod<bool>('hasPermissions') ?? false;
    final captured = await _channel.invokeListMethod<Map<Object?, Object?>>('captured') ?? const [];
    if (!mounted) return;
    setState(() {
      _permitted = permitted;
      _captured = captured;
    });
  }

  Future<void> _requestPermission() async {
    await _channel.invokeMethod<bool>('requestPermissions');
    await _refresh();
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    try {
      final rows = await _channel.invokeListMethod<Map<Object?, Object?>>(
            'scanInbox',
            {'limit': 500},
          ) ??
          const [];
      final report = analyze([
        for (final r in rows)
          (sender: r['sender']! as String, body: r['body']! as String),
      ]);
      if (mounted) setState(() => _report = report);
    } on PlatformException catch (e) {
      _toast(e.message ?? 'Scan failed');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _copyReport() async {
    await Clipboard.setData(ClipboardData(text: _report!.toShareableText()));
    _toast('মাস্ক করা রিপোর্ট কপি হয়েছে');
  }

  void _toast(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('SMS Probe')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'এই অ্যাপ শুধু bKash ও Nagad-এর SMS পড়ে। কিছুই ফোনের বাইরে যায় না।',
            ),
            const SizedBox(height: 16),
            if (!_permitted)
              FilledButton(
                onPressed: _requestPermission,
                child: const Text('SMS পড়ার অনুমতি দিন'),
              )
            else
              FilledButton(
                onPressed: _scanning ? null : _scan,
                child: Text(_scanning ? 'স্ক্যান হচ্ছে…' : 'পুরোনো SMS পরীক্ষা করুন'),
              ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => _channel.invokeMethod<void>('openBatterySettings'),
              child: const Text('ব্যাটারি সেটিংস খুলুন'),
            ),
            if (report != null) ...[
              const SizedBox(height: 24),
              Text('ফলাফল: ${report.total}টা SMS',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('টাকা আসার SMS-এ পুরো নম্বর: ${report.incomingWith(NumberVisibility.full)}'),
              Text('টাকা আসার SMS-এ আংশিক নম্বর: ${report.incomingWith(NumberVisibility.partial)}'),
              Text('টাকা আসার SMS-এ নম্বর নেই: ${report.incomingWith(NumberVisibility.none)}'),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: _copyReport,
                child: const Text('মাস্ক করা রিপোর্ট কপি করুন'),
              ),
              for (final t in report.templates)
                Card(
                  child: ListTile(
                    title: Text('${t.sender} ×${t.count} · নম্বর: ${t.visibility.name}'),
                    subtitle: Text(t.sample),
                  ),
                ),
            ],
            const SizedBox(height: 24),
            Text('নতুন ধরা SMS: ${_captured.length}টা',
                style: Theme.of(context).textTheme.titleMedium),
            const Text('অ্যাপ বন্ধ রেখে টাকা পাঠিয়ে দেখুন, তারপর এখানে ফিরে আসুন।'),
            for (final c in _captured)
              Card(
                child: ListTile(
                  title: Text('${c['sender']} · ${_lag(c)}'),
                  subtitle: Text(maskSms(c['body']! as String)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _lag(Map<Object?, Object?> c) {
    final lag = (c['capturedAt']! as int) - (c['smsTime']! as int);
    return '${(lag / 1000).toStringAsFixed(1)} সেকেন্ড পরে ধরা';
  }
}
