import 'dart:convert';

import 'package:flutter/services.dart';

class Crop {
  final String name, image, location, growth;
  const Crop(this.name, this.image, this.location, this.growth);
  factory Crop.fromJson(Map value) => Crop(
    value['name'],
    value['image'] ?? '',
    value['location'] ?? '',
    value['growth'] ?? 'Unknown',
  );
  static List<Crop>? _loaded;
  static Future<List<Crop>> load() async {
    if (_loaded != null) return _loaded!;
    final values =
        jsonDecode(await rootBundle.loadString('assets/crops.json')) as List;
    return _loaded = values.map((v) => Crop.fromJson(v)).toList();
  }
}

const islandNames = [
  'Plaza Island',
  'Meadow Island',
  'Beach Island',
  'Forest Island',
  'Glade Island',
  'Sunlit Island',
  'Frosted Island',
  'Forgotten Island',
  'Ancient Island',
  'Glittering Island',
  'Tangled Island',
  'The Bind Island',
  'Mythopia Island',
  'Everafter Island',
];
const biomeNames = [
  'Plaza',
  'Peaceful Meadow',
  'Dazzle Beach',
  'Forest of Valor',
  'Glade of Trust',
  'Sunlit Plateau',
  'Frosted Heights',
  'Forgotten Lands',
  "Ancient's Landing",
  'Glittering Dunes',
  'Wild Tangle',
  'The Bind',
  'Everafter',
  'Mythopia',
  'Wishing Alps',
  'Glamour Gulch',
  'Pixie Acres',
  'Drowsybloom Acre',
  'Gloommeadow',
  'Braveheart Grove',
  'Nectar Apiary',
  'Shipwreck Shores',
  'Candy Cove',
  'Kingdom of Oublié',
];
Map<String, dynamic> newLayout(
  String name,
  String template, {
  int width = 32,
  int height = 32,
}) => {
  'name': name,
  'template': template,
  'width': islandNames.contains(template) ? 65 : width,
  'height': islandNames.contains(template) ? 65 : height,
  'calibrated': islandNames.contains(template),
  'blocked': <int>[],
  'wells': islandNames.contains(template)
      ? [
          {'x': 29, 'y': 29, 'w': 6, 'h': 6},
        ]
      : <dynamic>[],
  'plots': <dynamic>[],
};
void migrateLayout(Map layout) {
  layout.putIfAbsent('template', () => 'Custom / legacy');
  layout.putIfAbsent('width', () => 32);
  layout.putIfAbsent('height', () => 32);
  layout.putIfAbsent('calibrated', () => false);
  layout.putIfAbsent('blocked', () => []);
  layout.putIfAbsent('wells', () => []);
}

bool canPlace(
  Map layout,
  int x,
  int y,
  int w,
  int h, {
  bool ignoreWells = false,
}) {
  final width = layout['width'] as int, height = layout['height'] as int;
  if (x < 0 || y < 0 || w < 1 || h < 1 || x + w > width || y + h > height) {
    return false;
  }
  final blocked = (layout['blocked'] as List).toSet();
  for (int dy = y; dy < y + h; dy++) {
    for (int dx = x; dx < x + w; dx++) {
      if (blocked.contains(dy * width + dx)) return false;
    }
  }
  if (!ignoreWells) {
    for (final well in layout['wells'] as List) {
      if (x < well['x'] + well['w'] &&
          x + w > well['x'] &&
          y < well['y'] + well['h'] &&
          y + h > well['y']) {
        return false;
      }
    }
  }
  return true;
}

(int, int)? firstSpace(Map layout, int w, int h) {
  for (int y = 0; y <= layout['height'] - h; y++) {
    for (int x = 0; x <= layout['width'] - w; x++) {
      if (canPlace(layout, x, y, w, h)) return (x, y);
    }
  }
  return null;
}
