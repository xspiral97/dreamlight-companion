import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;

import 'updater.dart';

import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'store.dart';
import 'wiki.dart';
import 'planner.dart';
import 'schedule.dart';

String selectedZone = 'Device local';
DateTime gameNow() => selectedZone == 'Device local'
    ? DateTime.now()
    : tz.TZDateTime.now(tz.getLocation(selectedZone));
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  final store = Store();
  await store.open();
  await store.seedCatalog();
  selectedZone = await store.get('timezone', 'Device local');
  runApp(CompanionApp(store: store));
}

class CompanionApp extends StatelessWidget {
  final Store store;
  const CompanionApp({super.key, required this.store});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Dreamlight Companion',
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF98CFAD),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF14231F),
      cardTheme: const CardThemeData(color: Color(0xFF20352E)),
    ),
    home: Home(store: store),
  );
}

class Home extends StatefulWidget {
  final Store store;
  const Home({super.key, required this.store});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  late final Wiki wiki = Wiki(widget.store);
  List<Map<String, Object?>> rows = [];
  String section = 'Farm Planner',
      query = '',
      area = 'All areas',
      progress = 'All';
  Map<String, dynamic> owned = {};
  bool syncing = false;
  bool caching = false;
  String status = 'Ready', last = 'Never';
  String appVersion = '0.2.1', updateStatus = '';
  bool updating = false;
  DateTime? retryAfter;
  Timer? timer;
  final search = TextEditingController();
  final destinations = ['Farm Planner', ...sections, 'Settings'];
  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
      refreshIfDue();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    search.dispose();
    wiki.client.close();
    super.dispose();
  }

  Future<void> load() async {
    final info = await PackageInfo.fromPlatform();
    appVersion = info.version;
    final r = await widget.store.catalog();
    final o = await widget.store.get('progress', {});
    final m = await widget.store.db.query(
      'meta',
      where: 'key=?',
      whereArgs: ['lastSync'],
    );
    if (!mounted) return;
    setState(() {
      rows = r;
      owned = Map<String, dynamic>.from(o);
      last = m.isEmpty ? 'Never' : m.first['value'] as String;
    });
    refreshIfDue();
  }

  Future<void> refreshIfDue() async {
    final date = DateTime.tryParse(last);
    if (!syncing &&
        (retryAfter == null || DateTime.now().isAfter(retryAfter!)) &&
        (date == null ||
            DateTime.now().difference(date) > const Duration(days: 1))) {
      await sync();
    }
  }

  Future<void> sync() async {
    if (syncing) return;
    setState(() => syncing = true);
    try {
      retryAfter = DateTime.now().add(const Duration(hours: 1));
      final report = await wiki.sync((s) {
        if (mounted) setState(() => status = s);
      });
      final r = await widget.store.catalog();
      if (mounted) {
        setState(() {
          rows = r;
          if (report.failures.isEmpty) {
            last = DateTime.now().toUtc().toIso8601String();
          }
          status = report.toString();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => status = 'Update failed; existing catalog retained. $e');
        message(status);
      }
    } finally {
      if (mounted) setState(() => syncing = false);
    }
  }

  Future<void> cacheDetails({bool companionsOnly = false}) async {
    if (caching) return;
    setState(() => caching = true);
    final targets = rows
        .where(
          (r) =>
              !companionsOnly ||
              sectionFor(r['title'] as String, r['categories'] as String) ==
                  'Companions',
        )
        .toList();
    int failed = 0;
    for (int i = 0; i < targets.length && mounted && caching; i++) {
      try {
        await wiki.details(targets[i]);
      } catch (e) {
        failed++;
      }
      if (mounted) {
        setState(
          () => status =
              'Offline details: ${i + 1}/${targets.length}; failures: $failed',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    final updated = await widget.store.catalog();
    if (mounted) {
      setState(() {
        rows = updated;
        caching = false;
      });
    }
  }

  Future<void> toggle(String id, bool value) async {
    setState(() => owned[id] = value);
    await widget.store.set('progress', owned);
  }

  Future<void> backup() async {
    try {
      final text = await widget.store.export();
      await FilePicker.saveFile(
        dialogTitle: 'Export personal backup',
        fileName: 'dreamlight-backup.json',
        bytes: Uint8List.fromList(utf8.encode(text)),
      );
    } catch (e) {
      message('$e');
    }
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> restore() async {
    try {
      final result = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || !mounted) return;
      final text = utf8.decode(await result.readAsBytes());
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Replace personal data?'),
          content: const Text(
            'Your layouts, progress and settings will be replaced. A backup of your current data will be saved automatically.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Import'),
            ),
          ],
        ),
      );
      if (ok == true) {
        await widget.store.restore(text);
        selectedZone = await widget.store.get('timezone', 'Device local');
        await load();
        if (mounted) setState(() => section = 'Settings');
        message('Backup imported.');
      }
    } catch (e) {
      message('Import failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 900;
    final nav = ListView(
      children: [
        const Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.auto_awesome, color: Color(0xFFE7C681), size: 32),
              SizedBox(height: 12),
              Text(
                'DREAMLIGHT',
                style: TextStyle(
                  letterSpacing: 3,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Your valley, remembered',
                style: TextStyle(color: Colors.white54),
              ),
            ],
          ),
        ),
        for (final d in destinations)
          ListTile(
            selected: section == d,
            selectedTileColor: const Color(0xFF304C40),
            leading: Icon(
              d == 'Farm Planner'
                  ? Icons.grid_view
                  : d == 'Settings'
                  ? Icons.settings
                  : Icons.menu_book_outlined,
              size: 20,
            ),
            title: Text(d),
            onTap: () {
              setState(() {
                section = d;
                area = 'All areas';
              });
              if (!wide) Navigator.pop(context);
            },
          ),
      ],
    );
    return Scaffold(
      appBar: wide ? null : AppBar(title: Text(section)),
      drawer: wide ? null : Drawer(child: nav),
      body: Row(
        children: [
          if (wide) SizedBox(width: 236, child: nav),
          if (wide) const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              section,
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            Text(
                              section == 'Farm Planner'
                                  ? 'Make room for your next harvest.'
                                  : 'Your guide to every corner of the Valley.',
                              style: const TextStyle(color: Colors.white60),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Refresh wiki catalog',
                        onPressed: syncing ? null : sync,
                        icon: const Icon(Icons.sync),
                      ),
                    ],
                  ),
                ),
                if (syncing) const LinearProgressIndicator(),
                Expanded(
                  child: section == 'Farm Planner'
                      ? Planner(
                          key: ValueKey(owned.hashCode),
                          store: widget.store,
                          crops: rows
                              .where(
                                (r) =>
                                    sectionFor(
                                      r['title'] as String,
                                      r['categories'] as String,
                                    ) ==
                                    'Ingredients',
                              )
                              .map((r) => r['title'] as String)
                              .toList(),
                        )
                      : section == 'Settings'
                      ? settings()
                      : catalog(),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  child: Text(
                    status == 'Ready'
                        ? '${rows.length} wiki pages · Last update: $last'
                        : status,
                    maxLines: 2,
                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> checkUpdates() async {
    final updater = AppUpdater();
    setState(() {
      updating = true;
      updateStatus = 'Checking GitHub Releases…';
    });
    try {
      final release = await updater.check(appVersion);
      if (!mounted) return;
      if (release == null) {
        setState(() => updateStatus = 'You are up to date ($appVersion).');
        return;
      }
      if (!Platform.isWindows && !Platform.isAndroid) {
        await launchUrl(Uri.parse(release.url));
        setState(
          () => updateStatus =
              'Download the package for your platform from the release page.',
        );
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Update to ${release.version}?'),
          content: SingleChildScrollView(
            child: Text(
              '${release.notes}\n\nThe app will download the update and restart. Your layouts and progress are kept.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Download and restart'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      if (Platform.isAndroid) {
        final apk = await updater.downloadAndroid(release, widget.store.home, (
          s,
        ) {
          if (mounted) setState(() => updateStatus = s);
        });
        await File(
          path.join(widget.store.home.path, 'updates', 'personal-backup.json'),
        ).writeAsString(await widget.store.export(), flush: true);
        await const MethodChannel('dreamlight_companion/updates')
            .invokeMethod('installApk', {'path': apk.path});
        if (mounted) {
          setState(
            () => updateStatus = 'Confirm the update in Android. Your app data will be preserved.',
          );
        }
        return;
      }
      final config = await updater.stage(release, widget.store.home, (s) {
        if (mounted) setState(() => updateStatus = s);
      });
      await File(path.join(config.parent.path, 'personal-backup.json'))
          .writeAsString(await widget.store.export(), flush: true);
      await updater.apply(config);
      timer?.cancel();
      wiki.client.close();
      await widget.store.db.close();
      exit(0);
    } catch (e) {
      if (mounted) setState(() => updateStatus = 'Update failed: $e');
    } finally {
      updater.client.close();
      if (mounted) setState(() => updating = false);
    }
  }

  Widget settings() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(
        'Dreamlight Companion $appVersion',
        style: const TextStyle(fontSize: 22),
      ),
      Text(updateStatus),
      FilledButton.icon(
        onPressed: updating || syncing || caching ? null : checkUpdates,
        icon: const Icon(Icons.system_update),
        label: const Text('Check for updates'),
      ),
      const SizedBox(height: 24),
      const Text('Offline library & backups', style: TextStyle(fontSize: 22)),
      DropdownButton<String>(
        isExpanded: true,
        value: selectedZone,
        items: [
          'Device local',
          ...tz.timeZoneDatabase.locations.keys.toList()..sort(),
        ].map((z) => DropdownMenuItem(value: z, child: Text(z))).toList(),
        onChanged: (z) async {
          await widget.store.set('timezone', z);
          setState(() => selectedZone = z!);
        },
      ),
      const SizedBox(height: 16),
      Text(status),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          FilledButton.icon(
            onPressed: syncing ? null : sync,
            icon: const Icon(Icons.cloud_download),
            label: const Text('Refresh now'),
          ),
          OutlinedButton(
            onPressed: caching
                ? null
                : () => cacheDetails(companionsOnly: true),
            child: const Text('Download companion details'),
          ),
          OutlinedButton(
            onPressed: caching ? null : () => cacheDetails(),
            child: const Text('Download all offline details'),
          ),
          if (caching)
            TextButton(
              onPressed: () => setState(() => caching = false),
              child: const Text('Stop download'),
            ),
          OutlinedButton(onPressed: backup, child: const Text('Export backup')),
          OutlinedButton(
            onPressed: restore,
            child: const Text('Import backup'),
          ),
        ],
      ),
      const SizedBox(height: 24),
      const Text(
        'Catalog pages are discovered automatically. Open an entry online to download its full details for offline reading. Unknown fields are left unspecified. Personal progress is entered manually.',
      ),
      const SizedBox(height: 24),
      const Text(
        'Source: Dreamlight Valley Wiki. Text: CC BY-NC-SA 4.0. Noncommercial use only. Game images © Disney / Gameloft. This is an unofficial companion application.',
      ),
      TextButton(
        onPressed: () => launchUrl(Uri.parse(Wiki.base)),
        child: const Text('Visit source wiki'),
      ),
      const Text(
        'Schedules and daily feeding marks use the selected time zone.',
      ),
    ],
  );
  Widget catalog() {
    final areas = <String>{};
    for (final r in rows) {
      for (final c
          in (jsonDecode(r['categories'] as String) as List).cast<String>()) {
        areas.add(c);
      }
    }
    final filtered = rows.where((r) {
      final id = r['id'] as String;
      return matchesSection(
            section,
            r['title'] as String,
            r['categories'] as String,
          ) &&
          (query.isEmpty ||
              '${r['title']} ${r['categories']}'.toLowerCase().contains(
                query.toLowerCase(),
              )) &&
          (area == 'All areas' || (r['categories'] as String).contains(area)) &&
          (progress == 'All' ||
              (owned[id] == true) == (progress == 'Collected'));
    }).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              TextField(
                controller: search,
                onChanged: (v) => setState(() => query = v),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search names, locations, DLCs…',
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: area,
                      items: ['All areas', ...areas.toList()..sort()]
                          .map(
                            (a) => DropdownMenuItem(
                              value: a,
                              child: Text(a, overflow: TextOverflow.ellipsis),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => area = v!),
                    ),
                  ),
                  const SizedBox(width: 16),
                  DropdownButton<String>(
                    value: progress,
                    items: ['All', 'Collected', 'Missing']
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (s) => setState(() => progress = s!),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    rows.isEmpty
                        ? 'Connect to the wiki using Refresh now to build your library.'
                        : 'No matching entries.',
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(20),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 340,
                    mainAxisExtent: 195,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (c, i) {
                    final r = filtered[i];
                    final cats = (jsonDecode(r['categories'] as String) as List)
                        .join(' · ');
                    final cached = r['details'] == null
                        ? null
                        : jsonDecode(r['details'] as String);
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => open(r),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.auto_awesome_outlined,
                                    color: Color(0xFFE7C681),
                                  ),
                                  const Spacer(),
                                  Checkbox(
                                    value: owned[r['id']] == true,
                                    onChanged: (v) =>
                                        toggle(r['id'] as String, v!),
                                  ),
                                ],
                              ),
                              Text(
                                r['title'] as String,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (cached != null &&
                                  (cached['schedule'] as List? ?? [])
                                      .isNotEmpty)
                                Text(
                                  availability(cached['schedule'], gameNow()),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF98CFAD),
                                  ),
                                ),
                              const SizedBox(height: 6),
                              Expanded(
                                child: Text(
                                  cats.isEmpty ? 'Guide' : cats,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white54,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> open(Map<String, Object?> row) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EntryPage(
          store: widget.store,
          wiki: wiki,
          row: row,
          onLink: (title) {
            final matches = rows.where((r) => r['title'] == title);
            if (matches.isNotEmpty) open(matches.first);
          },
        ),
      ),
    );
  }
}

class EntryPage extends StatefulWidget {
  final Store store;
  final Wiki wiki;
  final Map<String, Object?> row;
  final void Function(String) onLink;
  const EntryPage({
    super.key,
    required this.store,
    required this.wiki,
    required this.row,
    required this.onLink,
  });
  @override
  State<EntryPage> createState() => _EntryPageState();
}

class _EntryPageState extends State<EntryPage> {
  Map<String, dynamic>? data;
  String? error;
  bool loading = false, fed = false;
  final gifts = TextEditingController();
  String get day {
    final d = gameNow();
    return '${d.year}-${d.month}-${d.day}';
  }

  @override
  void initState() {
    super.initState();
    if (widget.row['details'] != null) {
      data = jsonDecode(widget.row['details'] as String);
    }
    load();
  }

  @override
  void dispose() {
    gifts.dispose();
    super.dispose();
  }

  Future<void> load() async {
    fed = await widget.store.get('fed:${widget.row['id']}:$day', false);
    gifts.text = await widget.store.get('gifts:${widget.row['id']}:$day', '');
    if (data == null ||
        data?['summary'] == true ||
        DateTime.now().difference(
              DateTime.tryParse(data?['fetchedAt'] ?? '') ?? DateTime(2000),
            ) >
            const Duration(days: 1)) {
      await refresh();
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> refresh() async {
    setState(() => loading = true);
    try {
      final d = await widget.wiki.details(widget.row);
      if (mounted) setState(() => data = d);
    } catch (e) {
      if (mounted) setState(() => error = 'Details unavailable: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fields = data?['fields'] as Map? ?? {};
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.row['title'] as String),
        actions: [
          IconButton(
            onPressed: loading ? null : refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: () =>
                launchUrl(Uri.parse('${Wiki.base}/?curid=${widget.row['id']}')),
            icon: const Icon(Icons.open_in_new),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (loading) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          if (data?['image'] != null)
            Align(
              alignment: Alignment.centerLeft,
              child: CachedNetworkImage(
                imageUrl: data!['image'],
                height: 160,
                errorWidget: (_, e, s) => const Icon(Icons.image_not_supported),
              ),
            ),
          const SizedBox(height: 16),
          if ((data?['schedule'] as List? ?? []).isNotEmpty)
            Text(
              availability(data!['schedule'], gameNow()),
              style: const TextStyle(fontSize: 22, color: Color(0xFF98CFAD)),
            ),
          for (final e in fields.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('${e.key}  ${e.value}'),
            ),
          if (sectionFor(
                widget.row['title'] as String,
                widget.row['categories'] as String,
              ) ==
              'Companions')
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Fed today'),
              subtitle: Text('Local date: $day'),
              value: fed,
              onChanged: (v) async {
                await widget.store.set('fed:${widget.row['id']}:$day', v);
                if (mounted) setState(() => fed = v!);
              },
            ),
          if (sectionFor(
                widget.row['title'] as String,
                widget.row['categories'] as String,
              ) ==
              'Characters')
            TextField(
              controller: gifts,
              decoration: const InputDecoration(
                labelText: 'Today’s favorite gifts (manual)',
              ),
              onChanged: (v) =>
                  widget.store.set('gifts:${widget.row['id']}:$day', v),
            ),
          for (final b in data?['blocks'] ?? [])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SelectableText(
                b['text'],
                style: TextStyle(
                  fontSize: b['type'] == 'h2'
                      ? 23
                      : b['type'] == 'h3'
                      ? 19
                      : 14,
                ),
              ),
            ),
          const Divider(),
          const Text('Related wiki entries'),
          Wrap(
            spacing: 8,
            children: [
              for (final link in (data?['links'] as List? ?? []).take(100))
                ActionChip(
                  label: Text('$link'),
                  onPressed: () => widget.onLink('$link'),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Dreamlight Valley Wiki · CC BY-NC-SA 4.0\nCached: ${data?['fetchedAt'] ?? 'Not downloaded'}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
