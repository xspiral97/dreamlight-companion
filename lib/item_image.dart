import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:html/dom.dart';

import 'wiki_http.dart';

String? itemImage(Document doc) {
  final figure = doc.querySelector('#infobox-image figure img');
  if (figure != null) return figure.attributes['src'];
  final images = doc.querySelectorAll('#infobox-image img')
    ..sort(
      (a, b) => (int.tryParse(b.attributes['width'] ?? '0') ?? 0).compareTo(
        int.tryParse(a.attributes['width'] ?? '0') ?? 0,
      ),
    );
  return images.firstOrNull?.attributes['src'];
}

List<String> imageCandidates(String? url) {
  if (url == null || url.isEmpty) return [];
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https') return [];
  final paths = uri.pathSegments;
  if (paths.length >= 6 && paths[0] == 'images' && paths[1] == 'thumb') {
    return [
      url,
      uri
          .replace(
            pathSegments: ['images', ...paths.sublist(2, paths.length - 1)],
          )
          .toString(),
    ];
  }
  return [url];
}

final bundledImageFiles = <String, String>{};
Future<void> initializeItemImages() async {
  final list =
      jsonDecode(await rootBundle.loadString('assets/crops.json')) as List;
  for (final item in list) {
    final url = item['imageSource'] as String?;
    if (url != null) {
      final parts = Uri.parse(url).pathSegments;
      bundledImageFiles[parts.contains('thumb')
              ? parts[parts.length - 2]
              : parts.last] =
          item['image'];
    }
  }
  bundledImageFiles['Wishing_Well.png'] = 'assets/icons/wishing_well.png';
}

String? localItemImage(String? url) {
  if (url == null) return null;
  final segments = Uri.tryParse(url)?.pathSegments ?? [];
  if (segments.isEmpty) return null;
  final name = segments.contains('thumb') && segments.length > 1
      ? segments[segments.length - 2]
      : segments.last;
  return bundledImageFiles[name];
}

final wikiImageCache = CacheManager(
  Config(
    'wiki-item-images-v2',
    stalePeriod: const Duration(days: 60),
    maxNrOfCacheObjects: 10000,
    fileService: HttpFileService(httpClient: WikiPacedClient())
      ..concurrentFetches = 3,
  ),
);

class ItemImage extends StatefulWidget {
  final String? url;
  final double size;
  const ItemImage({super.key, required this.url, this.size = 56});
  @override
  State<ItemImage> createState() => _ItemImageState();
}

class _ItemImageState extends State<ItemImage> {
  int candidate = 0;
  int generation = 0;
  bool retryQueued = false;
  @override
  void didUpdateWidget(covariant ItemImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      candidate = 0;
      retryQueued = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = localItemImage(widget.url);
    if (local != null) {
      return Image.asset(
        local,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
      );
    }
    final urls = imageCandidates(widget.url);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: urls.isEmpty
          ? const Icon(
              Icons.image_not_supported_outlined,
              color: Colors.white38,
            )
          : CachedNetworkImage(
              key: ValueKey('${urls[candidate]}-$candidate-$generation'),
              imageUrl: urls[candidate],
              cacheManager: wikiImageCache,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.contain,
              memCacheWidth: (widget.size * 2).ceil(),
              placeholder: (_, url) => const Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
              ),
              errorWidget: (_, url, error) {
                if (candidate + 1 < urls.length && !retryQueued) {
                  retryQueued = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() {
                        candidate++;
                        retryQueued = false;
                      });
                    }
                  });
                  return const Center(
                    child: Icon(
                      Icons.downloading_outlined,
                      color: Colors.white38,
                    ),
                  );
                }
                return Tooltip(
                  message: 'Image unavailable. Tap to retry.',
                  child: IconButton(
                    onPressed: () async {
                      await wikiImageCache.removeFile(url);
                      if (mounted) {
                        setState(() {
                          candidate = 0;
                          generation++;
                        });
                      }
                    },
                    icon: const Icon(Icons.refresh, color: Colors.white38),
                  ),
                );
              },
            ),
    );
  }
}
