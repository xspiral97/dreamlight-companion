import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

Duration retryDelay(String? header, {DateTime? now}) {
  final seconds = int.tryParse(header ?? '');
  if (seconds != null) return Duration(seconds: seconds.clamp(1, 86400));
  try {
    final date = HttpDate.parse(header!);
    final delay = date.difference(now ?? DateTime.now());
    return delay.isNegative
        ? const Duration(seconds: 1)
        : Duration(seconds: delay.inSeconds.clamp(1, 86400));
  } catch (_) {
    return const Duration(seconds: 60);
  }
}

class WikiPacedClient extends http.BaseClient {
  final http.Client inner;
  WikiPacedClient([http.Client? client]) : inner = client ?? http.Client();
  static Future<void> _queue = Future.value();
  static DateTime _nextApi = DateTime(2000),
      _nextImage = DateTime(2000),
      _apiPause = DateTime(2000),
      _imagePause = DateTime(2000);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!request.url.host.endsWith('dreamlightvalleywiki.com')) {
      return inner.send(request);
    }
    final previous = _queue;
    final gate = Completer<void>();
    _queue = gate.future;
    try {
      await previous;
      final api = request.url.path.endsWith('/api.php');
      final next = api ? _nextApi : _nextImage;
      final pause = api ? _apiPause : _imagePause;
      if (DateTime.now().isBefore(pause)) {
        throw http.ClientException(
          'Wiki cooldown until ${pause.toLocal()}. The offline catalog remains available.',
          request.url,
        );
      }
      final wait = next.difference(DateTime.now());
      if (!wait.isNegative) await Future<void>.delayed(wait);
      if (api) {
        _nextApi = DateTime.now().add(const Duration(seconds: 6));
      } else {
        _nextImage = DateTime.now().add(const Duration(milliseconds: 400));
      }
    } finally {
      gate.complete();
    }
    request.headers.putIfAbsent(
      'User-Agent',
      () => 'DreamlightCompanion/0.3 (noncommercial catalog; github.com/xspiral97/dreamlight-companion)',
    );
    final response = await inner.send(request);
    if (response.statusCode == 429) {
      final until = DateTime.now().add(
        retryDelay(response.headers['retry-after']),
      );
      if (request.url.path.endsWith('/api.php')) {
        _apiPause = until;
      } else {
        _imagePause = until;
      }
    }
    return response;
  }

  @override
  void close() => inner.close();
}
