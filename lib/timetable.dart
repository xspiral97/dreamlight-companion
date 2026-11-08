import 'dart:convert';

import 'package:flutter/material.dart';

import 'schedule.dart';
import 'store.dart';

String characterVenue(Map<String, dynamic> data, int hour) {
  final hours = (data['characterSchedule'] as Map?)?['hours'] as List?;
  return hours != null && hours.length == 24
      ? hours[hour].toString()
      : 'Unknown';
}

String eventStatus(Map event, DateTime now) {
  if (event['permanent'] == true) return 'Permanent';
  final start = DateTime.tryParse(event['start'] ?? '');
  final end = DateTime.tryParse(event['end'] ?? '');
  if (start == null || end == null) return 'Dates not specified';
  final date = DateTime(now.year, now.month, now.day);
  if (date.isBefore(start)) return 'Upcoming';
  if (date.isAfter(end)) return 'Past';
  return 'Current';
}

class ActivityTimetable extends StatefulWidget {
  final List<Map<String, Object?>> rows;
  final bool companions;
  final DateTime now;
  final String zone;
  final void Function(Map<String, Object?>) onOpen;
  const ActivityTimetable({
    super.key,
    required this.rows,
    required this.companions,
    required this.now,
    required this.zone,
    required this.onOpen,
  });
  @override
  State<ActivityTimetable> createState() => _ActivityTimetableState();
}

class _ActivityTimetableState extends State<ActivityTimetable> {
  final header = ScrollController(),
      body = ScrollController(),
      vertical = ScrollController();
  late int day;
  bool syncing = false, centered = false;
  static const cellWidth = 60.0, rowHeight = 68.0;
  @override
  void initState() {
    super.initState();
    day = widget.now.weekday;
    header.addListener(() => syncScroll(header, body));
    body.addListener(() => syncScroll(body, header));
  }

  @override
  void didUpdateWidget(covariant ActivityTimetable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.now.weekday != widget.now.weekday &&
        day == oldWidget.now.weekday) {
      day = widget.now.weekday;
    }
  }

  void syncScroll(ScrollController from, ScrollController to) {
    if (syncing || !from.hasClients || !to.hasClients) return;
    syncing = true;
    to.jumpTo(from.offset.clamp(0, to.position.maxScrollExtent));
    syncing = false;
  }

  @override
  void dispose() {
    header.dispose();
    body.dispose();
    vertical.dispose();
    super.dispose();
  }

  void showNow() {
    setState(() => day = widget.now.weekday);
    if (body.hasClients) {
      body.jumpTo(
        (widget.now.hour * cellWidth - body.position.viewportDimension / 2)
            .clamp(0, body.position.maxScrollExtent),
      );
    }
  }

  Map<String, dynamic> data(Map row) => row['details'] == null
      ? {}
      : Map<String, dynamic>.from(jsonDecode(row['details'] as String));
  bool availableAt(Map<String, dynamic> value, int hour) =>
      ((value['schedule'] as List?) ?? []).any(
        (w) => inWindow(
          DateTime(2026, 11, 2 + day - 1, hour),
          w['day'],
          w['start'],
          w['end'],
        ),
      );
  Color color(String state) => switch (state) {
    'Home' => const Color(0xFF536FA4),
    'Restaurant' => const Color(0xFF45855D),
    "Scrooge's Store" => const Color(0xFFA27D39),
    'Grand Exhibition' => const Color(0xFF97617F),
    'Available' => const Color(0xFF3F805E),
    'Unavailable' => const Color(0xFF24392F),
    _ => const Color(0xFF293F36),
  };
  String stateAt(Map<String, dynamic> value, int hour) => widget.companions
      ? availableAt(value, hour)
            ? 'Available'
            : 'Unavailable'
      : characterVenue(value, hour);
  Widget hourHeader() => SizedBox(
    width: 24 * cellWidth,
    height: 42,
    child: Row(
      children: List.generate(
        24,
        (hour) => Container(
          width: cellWidth,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hour == widget.now.hour
                ? const Color(0xFFAA8040)
                : const Color(0xFF20352E),
            border: Border.all(
              color: hour == widget.now.hour
                  ? const Color(0xFFFFD782)
                  : Colors.white12,
            ),
          ),
          child: Text('${hour.toString().padLeft(2, '0')}:00'),
        ),
      ),
    ),
  );
  Widget label(Map<String, Object?> row) {
    final value = data(row);
    final info = value['companion'] as Map?;
    final location = info?['location'] ?? 'Unknown';
    final hours = (info?['weekly'] as Map?)?[weekdays[day - 1]] ?? 'Unknown';
    return SizedBox(
      height: rowHeight,
      child: InkWell(
        onTap: () => widget.onOpen(row),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                row['title'] as String,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 3),
              Expanded(
                child: Text(
                  widget.companions
                      ? '$location\n$hours'
                      : 'Now: ${characterVenue(value, widget.now.hour)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: Colors.white60),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget cells(Map<String, Object?> row) {
    final value = data(row);
    return SizedBox(
      height: rowHeight,
      child: Row(
        children: List.generate(24, (hour) {
          final state = stateAt(value, hour);
          final short = switch (state) {
            'Available' => 'Yes',
            'Unavailable' => '—',
            'Restaurant' => 'Eat',
            "Scrooge's Store" => 'Shop',
            'Grand Exhibition' => 'Exhibit',
            'Home' => 'Home',
            'Unknown' => '?',
            _ => 'Free',
          };
          return Tooltip(
            message:
                '${row['title']} · ${hour.toString().padLeft(2, '0')}:00 · $state${widget.companions ? ' · ${value['companion']['location']}' : ''}',
            child: Container(
              key: hour == widget.now.hour
                  ? ValueKey('current-hour-${row['id']}')
                  : null,
              width: cellWidth,
              height: rowHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color(state),
                border: Border.all(
                  color: hour == widget.now.hour
                      ? const Color(0xFFFFD782)
                      : const Color(0xFF172B23),
                  width: hour == widget.now.hour ? 2 : 1,
                ),
              ),
              child: Text(short, style: const TextStyle(fontSize: 10)),
            ),
          );
        }),
      ),
    );
  }

  Widget grid(List<Map<String, Object?>> rows, double labelWidth) {
    return Scrollbar(
      controller: vertical,
      child: SingleChildScrollView(
        controller: vertical,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: labelWidth,
              child: Column(children: rows.map(label).toList()),
            ),
            Expanded(
              child: Scrollbar(
                controller: body,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: body,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: 24 * cellWidth,
                    child: Column(children: rows.map(cells).toList()),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.companions
        ? widget.rows
              .where(
                (row) => (data(row)['companion'] as Map?)?['scheduled'] == true,
              )
              .toList()
        : widget.rows;
    final time =
        '${widget.now.hour.toString().padLeft(2, '0')}:${widget.now.minute.toString().padLeft(2, '0')}';
    final legend = widget.companions
        ? ['Available', 'Unavailable']
        : [
            'Home',
            'Restaurant',
            "Scrooge's Store",
            'Grand Exhibition',
            'Free / no fixed venue listed',
          ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final labelWidth = constraints.maxWidth < 600 ? 156.0 : 260.0;
        if (!centered && rows.isNotEmpty) {
          centered = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) showNow();
          });
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Wrap(
                spacing: 14,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Local now: ${weekdays[widget.now.weekday - 1]} $time · ${widget.zone}',
                    key: const Key('timetable-local-time'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFFD782),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: showNow,
                    child: const Text('Jump to now'),
                  ),
                  if (widget.companions)
                    DropdownButton<int>(
                      value: day,
                      items: List.generate(
                        7,
                        (i) => DropdownMenuItem(
                          value: i + 1,
                          child: Text(weekdays[i]),
                        ),
                      ),
                      onChanged: (value) => setState(() => day = value!),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                widget.companions
                    ? 'Choose a day to plan your visit. Green cells show appearances; amber marks the current local hour. Locations stay visible while scrolling.'
                    : 'Community schedule, not live position tracking. Restaurant = Chez Remy or Tiana’s Palace. Quests and stations may override it. Source: Dreamlight Valley Wiki / Time.',
                style: const TextStyle(fontSize: 11, color: Colors.white60),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(
                spacing: 12,
                children: [
                  for (final state in legend)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 12, height: 12, color: color(state)),
                        const SizedBox(width: 4),
                        Text(state, style: const TextStyle(fontSize: 10)),
                      ],
                    ),
                ],
              ),
            ),
            Row(
              children: [
                SizedBox(
                  width: labelWidth,
                  height: 42,
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Text('Who / where'),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: header,
                    scrollDirection: Axis.horizontal,
                    child: hourHeader(),
                  ),
                ),
              ],
            ),
            Expanded(
              child: rows.isEmpty
                  ? const Center(
                      child: Text('No scheduled entries match these filters.'),
                    )
                  : grid(rows, labelWidth),
            ),
          ],
        );
      },
    );
  }
}
