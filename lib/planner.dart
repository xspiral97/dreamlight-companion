import 'dart:math' as math;
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'farm_model.dart';
import 'store.dart';

class CropImage extends StatelessWidget {
  final Crop crop;
  final double size;
  const CropImage({super.key, required this.crop, this.size = 40});
  @override
  Widget build(BuildContext context) => crop.image.startsWith('assets/')
      ? Image.asset(crop.image, width: size, height: size, fit: BoxFit.contain)
      : CachedNetworkImage(
          imageUrl: crop.image,
          width: size,
          height: size,
          errorWidget: (_, e, s) => const Icon(Icons.grass),
        );
}

class Planner extends StatefulWidget {
  final Store store;
  final List<String> crops;
  const Planner({super.key, required this.store, this.crops = const []});
  @override
  State<Planner> createState() => _PlannerState();
}

class _PlannerState extends State<Planner> {
  List<dynamic> layouts = [];
  List<Crop> crops = [];
  int current = 0;
  int? selected;
  bool blockMode = false, subgrid = false;
  final transform = TransformationController();
  Map get layout => layouts[current] as Map;
  List get plots => layout['plots'] as List;
  static const tile = 24.0;
  static const palette = [
    Color(0xFFE2A94E),
    Color(0xFF8EBE91),
    Color(0xFFB69CDA),
    Color(0xFF76BCCC),
    Color(0xFFDB8F9F),
  ];
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final saved = await widget.store.get('layouts', [
      newLayout('My floating island', 'Plaza Island'),
    ]);
    final bundled = await Crop.load();
    final images = [...bundled];
    final cropRows = await widget.store.db.query(
      'meta',
      where: 'key=?',
      whereArgs: ['plantableCrops'],
    );
    final extra = cropRows.isEmpty
        ? []
        : jsonDecode(cropRows.first['value'] as String) as List;
    for (final raw in extra) {
      final crop = Crop.fromJson(raw);
      if (!images.any((c) => c.name == crop.name)) images.add(crop);
    }
    final original = jsonEncode(saved);
    for (final entry in saved) {
      migrateLayout(entry);
    }
    if (jsonEncode(saved) != original) {
      final backup = File(
        path.join(
          widget.store.home.path,
          'layouts-before-well-repair-${DateTime.now().millisecondsSinceEpoch}.json',
        ),
      );
      await backup.writeAsString(original, flush: true);
      await widget.store.set('layouts', saved);
    }
    if (mounted) {
      setState(() {
        layouts = saved;
        crops = images;
      });
    }
  }

  Future<void> save() async {
    await widget.store.set('layouts', layouts);
    if (mounted) setState(() {});
  }

  Future<void> deleteSelectedPlot() async {
    if (selected == null) return;
    final target = layout;
    final index = selected!;
    final removed = plots.removeAt(index);
    selected = null;
    await save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Deleted ${removed['crop']} plot.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            final entries = target['plots'] as List;
            entries.insert(index.clamp(0, entries.length), removed);
            save();
          },
        ),
      ),
    );
  }

  void message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Crop? cropFor(String name) {
    for (final crop in crops) {
      if (crop.name == name) return crop;
    }
    return null;
  }

  Future<void> configure({bool create = false}) async {
    final name = TextEditingController(text: create ? '' : layout['name']);
    String template = create ? 'Plaza Island' : layout['template'];
    final width = TextEditingController(
          text: '${create ? 65 : layout['width']}',
        ),
        height = TextEditingController(
          text: '${create ? 65 : layout['height']}',
        );
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(create ? 'New island / biome' : 'Map grid settings'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Layout name'),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: template,
                    isExpanded: true,
                    items:
                        {
                              template,
                              ...islandNames,
                              ...biomeNames,
                              'Custom / legacy',
                            }
                            .map(
                              (t) => DropdownMenuItem(
                                value: t,
                                child: Text(t, overflow: TextOverflow.ellipsis),
                              ),
                            )
                            .toList(),
                    onChanged: (v) => update(() {
                      template = v!;
                      if (islandNames.contains(v)) {
                        width.text = '65';
                        height.text = '65';
                      }
                    }),
                    decoration: const InputDecoration(
                      labelText: 'Map / floating island',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    islandNames.contains(template)
                        ? 'Floating island: 65 × 65 planting cells = 130 × 130 placement units. Well footprint: 6 × 6 planting cells (12 × 12 placement units). Its position can be adjusted.'
                        : 'Exact terrain dimensions are not verified for this map. Enter measured planting-cell bounds, then mark blocked cells. No terrain mask is assumed.',
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: width,
                          enabled: !islandNames.contains(template),
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Width (planting cells)',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: height,
                          enabled: !islandNames.contains(template),
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Height (planting cells)',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final w = int.tryParse(width.text),
                    h = int.tryParse(height.text);
                if (name.text.trim().isEmpty ||
                    w == null ||
                    h == null ||
                    w < 6 ||
                    h < 6 ||
                    w > 256 ||
                    h > 256) {
                  update(
                    () => error = 'Enter a name and dimensions from 6 to 256.',
                  );
                  return;
                }
                if (!create &&
                    [
                      ...plots,
                      ...layout['wells'],
                    ].any((p) => p['x'] + p['w'] > w || p['y'] + p['h'] > h)) {
                  update(
                    () => error = 'Existing plots or the well would fall outside these bounds. Move them first.',
                  );
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      final w = int.parse(width.text), h = int.parse(height.text);
      if (create) {
        layouts.add(newLayout(name.text.trim(), template, width: w, height: h));
        current = layouts.length - 1;
        selected = null;
      } else {
        final oldW = layout['width'] as int;
        final converted = <int>[];
        for (final cell in layout['blocked']) {
          final x = (cell as int) % oldW, y = cell ~/ oldW;
          if (x < w && y < h) converted.add(y * w + x);
        }
        layout['blocked'] = converted;
        layout['name'] = name.text.trim();
        layout['template'] = template;
        layout['width'] = w;
        layout['height'] = h;
        layout['calibrated'] = true;
        layout['wells'] = (layout['wells'] as List)
            .where((v) => v['x'] + v['w'] <= w && v['y'] + v['h'] <= h)
            .toList();
      }
      await save();
    }
    name.dispose();
    width.dispose();
    height.dispose();
  }

  Future<void> edit() async {
    final plot = selected == null ? null : plots[selected!];
    final name = TextEditingController(text: plot?['crop'] ?? 'Pumpkin');
    final notes = TextEditingController(text: plot?['notes'] ?? '');
    final width = TextEditingController(text: '${plot?['w'] ?? 4}'),
        height = TextEditingController(text: '${plot?['h'] ?? 4}');
    int color = plot?['color'] ?? 0;
    String query = '';
    String? error;
    final value = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('Edit crop plot'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Crop'),
                  ),
                  TextField(
                    decoration: InputDecoration(
                      labelText: 'Search ${crops.length} plantable crops',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) => update(() => query = v),
                  ),
                  SizedBox(
                    height: 170,
                    child: GridView.extent(
                      maxCrossAxisExtent: 105,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                      childAspectRatio: .95,
                      children: [
                        for (final crop in crops.where(
                          (c) => c.name.toLowerCase().contains(
                            query.toLowerCase(),
                          ),
                        ))
                          InkWell(
                            onTap: () => update(() => name.text = crop.name),
                            child: Container(
                              decoration: BoxDecoration(
                                color: name.text == crop.name
                                    ? palette[1].withValues(alpha: .3)
                                    : Colors.white.withValues(alpha: .04),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.all(4),
                              child: Column(
                                children: [
                                  CropImage(crop: crop),
                                  Text(
                                    crop.name,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: width,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Width (plants)',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: height,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Height (plants)',
                          ),
                        ),
                      ),
                    ],
                  ),
                  TextField(
                    controller: notes,
                    decoration: const InputDecoration(labelText: 'Notes'),
                    maxLines: 2,
                  ),
                  Wrap(
                    children: List.generate(
                      5,
                      (i) => IconButton(
                        onPressed: () => update(() => color = i),
                        icon: Icon(
                          color == i ? Icons.check_circle : Icons.circle,
                          color: palette[i],
                        ),
                      ),
                    ),
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final w = int.tryParse(width.text),
                    h = int.tryParse(height.text);
                if (name.text.trim().isEmpty ||
                    w == null ||
                    h == null ||
                    w < 1 ||
                    h < 1 ||
                    w > layout['width'] ||
                    h > layout['height']) {
                  update(
                    () => error = 'Enter a crop and a size that fits this map.',
                  );
                  return;
                }
                final pos =
                    plot != null &&
                        canPlace(
                          layout,
                          (plot['x'] as num).round(),
                          (plot['y'] as num).round(),
                          w,
                          h,
                        )
                    ? ((plot['x'] as num).round(), (plot['y'] as num).round())
                    : firstSpace(layout, w, h);
                if (pos == null) {
                  update(
                    () => error =
                        'No space: blocked terrain or well overlaps this plot.',
                  );
                  return;
                }
                Navigator.pop(ctx, {
                  'crop': name.text.trim(),
                  'notes': notes.text,
                  'w': w,
                  'h': h,
                  'x': pos.$1,
                  'y': pos.$2,
                  'color': color,
                });
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (value != null) {
      if (selected == null) {
        plots.add(value);
        selected = plots.length - 1;
      } else {
        plots[selected!] = value;
      }
      await save();
    }
    name.dispose();
    notes.dispose();
    width.dispose();
    height.dispose();
  }

  void blockAt(Offset point) {
    final x = (point.dx / tile).floor(), y = (point.dy / tile).floor();
    if (x < 0 || y < 0 || x >= layout['width'] || y >= layout['height']) return;
    final cell = y * (layout['width'] as int) + x;
    final blocked = layout['blocked'] as List;
    if (blocked.contains(cell)) {
      blocked.remove(cell);
    } else {
      if (plots.any(
            (p) =>
                x >= p['x'] &&
                x < p['x'] + p['w'] &&
                y >= p['y'] &&
                y < p['y'] + p['h'],
          ) ||
          (layout['wells'] as List).any(
            (p) =>
                x >= p['x'] &&
                x < p['x'] + p['w'] &&
                y >= p['y'] &&
                y < p['y'] + p['h'],
          )) {
        message('Move the plot or well before blocking this cell.');
        return;
      }
      blocked.add(cell);
    }
    save();
  }

  void move(Map object, Offset delta, {bool well = false}) {
    final oldX = (object['x'] as num).toDouble(),
        oldY = (object['y'] as num).toDouble();
    final nx = (oldX + delta.dx / tile).clamp(0, layout['width'] - object['w']),
        ny = (oldY + delta.dy / tile).clamp(0, layout['height'] - object['h']);
    if (canPlace(
          layout,
          nx.round(),
          ny.round(),
          object['w'],
          object['h'],
          ignoreWells: well,
        ) &&
        (!well ||
            !plots.any(
              (p) =>
                  nx < p['x'] + p['w'] &&
                  nx + object['w'] > p['x'] &&
                  ny < p['y'] + p['h'] &&
                  ny + object['h'] > p['y'],
            ))) {
      setState(() {
        object['x'] = nx;
        object['y'] = ny;
      });
    }
  }

  void snap(Map object) {
    object['x'] = (object['x'] as num).round();
    object['y'] = (object['y'] as num).round();
    save();
  }

  @override
  Widget build(BuildContext context) {
    if (layouts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final w = layout['width'] as int, h = layout['height'] as int;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 190,
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: current,
                  items: List.generate(
                    layouts.length,
                    (i) => DropdownMenuItem(
                      value: i,
                      child: Text(
                        layouts[i]['name'],
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  onChanged: (v) => setState(() {
                    current = v!;
                    selected = null;
                    blockMode = false;
                    transform.value = Matrix4.identity();
                  }),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => configure(create: true),
                icon: const Icon(Icons.add),
                label: const Text('New layout'),
              ),
              IconButton(
                tooltip: 'Map grid settings',
                onPressed: () => configure(),
                icon: const Icon(Icons.map_outlined),
              ),
              FilledButton.icon(
                onPressed: () {
                  selected = null;
                  edit();
                },
                icon: const Icon(Icons.grass),
                label: const Text('Add crop plot'),
              ),
              FilterChip(
                selected: blockMode,
                label: const Text('Mark blocked cells'),
                onSelected: (v) => setState(() => blockMode = v),
              ),
              FilterChip(
                selected: subgrid,
                label: const Text('Placement subgrid'),
                onSelected: (v) => setState(() => subgrid = v),
              ),
              const Chip(
                avatar: Icon(Icons.water_drop, size: 18),
                label: Text('1 well · drag to move'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '$w × $h planting cells · ${w * 2} × ${h * 2} placement units · ${layout['blocked'].length} blocked cells\n${layout['template']} · ${layout['calibrated'] == true ? 'Bounds configured' : 'Legacy / unverified bounds: configure map'} · Drag plots / wells. ${blockMode ? 'Tap a cell to toggle blocked terrain.' : 'Pinch / scroll to zoom.'}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: selected == null
              ? const Text(
                  'Tap a crop plot to select it, then edit or delete it.',
                  style: TextStyle(fontSize: 12),
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Selected: ${plots[selected!]['crop']}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: edit,
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('Edit crop'),
                    ),
                    OutlinedButton.icon(
                      onPressed: deleteSelectedPlot,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Delete crop'),
                    ),
                  ],
                ),
        ),
        Expanded(
          child: InteractiveViewer(
            transformationController: transform,
            minScale: .1,
            maxScale: 4,
            constrained: false,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: w * tile,
                height: h * tile,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        onTapDown: blockMode
                            ? (d) => blockAt(d.localPosition)
                            : null,
                        child: CustomPaint(
                          painter: _Grid(
                            w,
                            h,
                            (layout['blocked'] as List).cast<int>().toSet(),
                            subgrid,
                          ),
                        ),
                      ),
                    ),
                    for (int i = 0; i < plots.length; i++)
                      Positioned(
                        left: plots[i]['x'] * tile,
                        top: plots[i]['y'] * tile,
                        width: plots[i]['w'] * tile,
                        height: plots[i]['h'] * tile,
                        child: IgnorePointer(
                          ignoring: blockMode,
                          child: GestureDetector(
                            onTap: () => setState(() => selected = i),
                            onDoubleTap: () {
                              selected = i;
                              edit();
                            },
                            onPanUpdate: (d) {
                              selected = i;
                              move(plots[i], d.delta);
                            },
                            onPanEnd: (_) => snap(plots[i]),
                            child: Container(
                              clipBehavior: Clip.hardEdge,
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: palette[plots[i]['color']].withValues(
                                  alpha: .8,
                                ),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: selected == i
                                      ? Colors.white
                                      : Colors.black26,
                                  width: selected == i ? 3 : 1,
                                ),
                              ),
                              child: LayoutBuilder(
                                builder: (ctx, bounds) {
                                  final crop = cropFor(plots[i]['crop']);
                                  return Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (crop != null &&
                                          bounds.maxHeight >= 42)
                                        CropImage(
                                          crop: crop,
                                          size: math.min(
                                            38,
                                            bounds.maxHeight * .4,
                                          ),
                                        ),
                                      if (bounds.maxHeight >= 20)
                                        Flexible(
                                          child: Text(
                                            '${plots[i]['crop']}\n${plots[i]['w'] * plots[i]['h']} plants',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFF182820),
                                              fontWeight: FontWeight.bold,
                                            ),
                                            overflow: TextOverflow.fade,
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    for (final well in layout['wells'])
                      Positioned(
                        left: well['x'] * tile,
                        top: well['y'] * tile,
                        width: well['w'] * tile,
                        height: well['h'] * tile,
                        child: IgnorePointer(
                          ignoring: blockMode,
                          child: GestureDetector(
                            onPanUpdate: (d) => move(well, d.delta, well: true),
                            onPanEnd: (_) => snap(well),
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF46788B),
                                border: Border.all(
                                  color: Colors.lightBlueAccent,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: Image.asset(
                                      'assets/icons/wishing_well.png',
                                      height: 70,
                                      width: 70,
                                    ),
                                  ),
                                  const Text(
                                    'Wishing well',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  Text(
                                    '12 × 12 placement units',
                                    style: TextStyle(fontSize: 10),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (selected != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '${plots[selected!]['crop']} · ${plots[selected!]['notes']}',
            ),
          ),
      ],
    );
  }
}

class _Grid extends CustomPainter {
  final int width, height;
  final Set<int> blocked;
  final bool subgrid;
  _Grid(this.width, this.height, this.blocked, this.subgrid);
  @override
  void paint(Canvas c, Size s) {
    c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF20382F));
    for (final cell in blocked) {
      final x = cell % width * 24.0, y = cell ~/ width * 24.0;
      c.drawRect(
        Rect.fromLTWH(x, y, 24, 24),
        Paint()..color = const Color(0xFF5A4244),
      );
      c.drawLine(
        Offset(x + 3, y + 3),
        Offset(x + 21, y + 21),
        Paint()..color = Colors.redAccent.withValues(alpha: .55),
      );
    }
    final step = subgrid ? 12.0 : 24.0;
    for (double x = 0; x <= s.width; x += step) {
      c.drawLine(
        Offset(x, 0),
        Offset(x, s.height),
        Paint()
          ..color = const Color(0xFF4B685A)
          ..strokeWidth = x % 24 == 0 ? 0.6 : 0.25,
      );
    }
    for (double y = 0; y <= s.height; y += step) {
      c.drawLine(
        Offset(0, y),
        Offset(s.width, y),
        Paint()
          ..color = const Color(0xFF4B685A)
          ..strokeWidth = y % 24 == 0 ? 0.6 : 0.25,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _Grid old) => true;
}
