/// Reads the link in the dashboard's pairing QR.
library;

class PairLink {
  const PairLink(this.serverUrl, this.code);

  final String serverUrl;
  final String code;

  String get host => Uri.parse(serverUrl).host;
}

/// Returns null for anything that is not a valid pairing link. A QR code can
/// come from anyone, so the server address is checked before it is used.
PairLink? parsePairLink(
  String raw, {
  required bool allowHttp,
  String pinnedServer = '',
}) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.scheme != 'univapayment' || uri.host != 'pair') return null;

  final code = uri.queryParameters['code']?.trim() ?? '';
  final server = uri.queryParameters['url']?.trim() ?? '';
  final target = Uri.tryParse(server);
  if (code.isEmpty || target == null || target.host.isEmpty) return null;
  if (target.userInfo.isNotEmpty) return null;
  if (target.scheme != 'https' && !(allowHttp && target.scheme == 'http')) return null;

  // A build made for one server never connects to another.
  if (pinnedServer.isNotEmpty) {
    final pinned = Uri.tryParse(pinnedServer);
    if (pinned == null || pinned.host != target.host) return null;
  }
  return PairLink(server, code);
}
