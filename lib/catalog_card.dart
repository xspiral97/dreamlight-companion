import 'package:flutter/material.dart';

import 'item_image.dart';
import 'schedule.dart';
import 'store.dart';
import 'timetable.dart';

enum CompanionAvailability { available, unavailable, unknown, notScheduled }

CompanionAvailability companionAvailability(
  Map<String, dynamic> data,
  DateTime now,
) {
  final info = data['companion'] as Map?;
  if (info?['scheduled'] == false) return CompanionAvailability.notScheduled;
  if (info?['scheduleVerified'] != true) return CompanionAvailability.unknown;
  final windows = data['schedule'] as List? ?? [];
  return windows.any((w) => inWindow(now, w['day'], w['start'], w['end']))
      ? CompanionAvailability.available
      : CompanionAvailability.unavailable;
}

String companionStatus(Map<String, dynamic> data, DateTime now) {
  switch (companionAvailability(data, now)) {
    case CompanionAvailability.available:
      return 'Available now';
    case CompanionAvailability.unavailable:
      return availability(
        data['schedule'] ?? [],
        now,
      ).replaceFirst('Schedule unknown', 'No upcoming hours listed');
    case CompanionAvailability.unknown:
      return 'Schedule not known';
    case CompanionAvailability.notScheduled:
      return 'Not a scheduled wild critter';
  }
}

String companionFood(Map<String, dynamic> data, String kind) {
  final info = data['companion'] as Map?;
  final fields = data['fields'] as Map?;
  return fieldText(
    info?[kind.toLowerCase()] ??
        fields?['$kind food:'] ??
        fields?['$kind Food:'],
  );
}

class CompanionSourceBadge extends StatelessWidget {
  final Map info;
  const CompanionSourceBadge({super.key, required this.info});
  @override
  Widget build(BuildContext context) {
    final tags =
        (info['acquisition'] as Map?)?['tags'] as List? ?? ['Unknown source'];
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final tag in tags)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: tag.toString().contains('Premium') || tag == 'Star Path'
                  ? const Color(0xFF66523B)
                  : const Color(0xFF304C40),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              '$tag',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }
}

String todayHours(Map<String, dynamic> data, DateTime now) =>
    ((data['companion'] as Map?)?['weekly'] as Map?)?[weekdays[now.weekday - 1]]
        ?.toString() ??
    'Unknown';
String fieldText(dynamic value, [String fallback = 'Unknown']) =>
    value == null || value.toString().trim().isEmpty
    ? fallback
    : value.toString();

class CatalogCard extends StatelessWidget {
  final String title, categories, section;
  final Map<String, dynamic> data;
  final String? image;
  final DateTime now;
  final bool collected;
  final VoidCallback onOpen;
  final ValueChanged<bool> onCollected;
  const CatalogCard({
    super.key,
    required this.title,
    required this.categories,
    required this.section,
    required this.data,
    required this.image,
    required this.now,
    required this.collected,
    required this.onOpen,
    required this.onCollected,
  });
  Widget line(String label, dynamic text, {int lines = 2, Color? color}) =>
      Tooltip(
        message: '$label: ${fieldText(text)}',
        child: Text(
          '$label: ${fieldText(text)}',
          maxLines: lines,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            color: color ?? Colors.white70,
            height: 1.2,
          ),
        ),
      );
  @override
  Widget build(BuildContext context) {
    final fish = data['fishing'] as Map?;
    final companion = data['companion'] as Map?;
    final state = companionAvailability(data, now);
    final unavailable =
        section == 'Companions' && state == CompanionAvailability.unavailable;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ItemImage(url: image, size: 48),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Tooltip(
                      message: title,
                      child: Text(
                        title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: unavailable ? Colors.white54 : null,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 22,
                    height: 24,
                    child: Checkbox(
                      value: collected,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (v) => onCollected(v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (section == 'Fish') ...[
                line('Ripple', fish?['ripples']),
                const SizedBox(height: 3),
                line('Weather', fish?['weather']),
                const SizedBox(height: 3),
                line('Time', fish?['time']),
                const SizedBox(height: 3),
                Expanded(child: line('Zone', fish?['locations'], lines: 3)),
              ] else if (section == 'Companions') ...[
                CompanionSourceBadge(info: companion ?? {}),
                const SizedBox(height: 5),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (companion?['scheduled'] == true) ...[
                          Text(
                            companionStatus(data, now),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: state == CompanionAvailability.available
                                  ? const Color(0xFF98CFAD)
                                  : Colors.white54,
                            ),
                          ),
                          const SizedBox(height: 4),
                          line(
                            'Favorite',
                            companionFood(data, 'Favorite'),
                            lines: 6,
                          ),
                          const SizedBox(height: 4),
                          line(
                            'Liked',
                            companionFood(data, 'Liked'),
                            lines: 12,
                          ),
                          const SizedBox(height: 4),
                          line('Location', companion?['location'], lines: 3),
                          const SizedBox(height: 4),
                          line('Today', todayHours(data, now), lines: 3),
                        ] else ...[
                          line(
                            'Obtain',
                            (companion?['acquisition'] as Map?)?['description'],
                            lines: 8,
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Unlocked without wild feeding.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white60,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ] else if (section == 'Ingredients') ...[
                Expanded(
                  child: line(
                    'Zone',
                    (data['ingredient'] as Map?)?['locations'] ??
                        (data['fields'] as Map?)?['Zones:'],
                    lines: 5,
                  ),
                ),
              ] else if (section == 'Recipes') ...[
                Text(
                  fieldText((data['recipe'] as Map?)?['category']),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF98CFAD),
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: line(
                    'Ingredients',
                    ((data['recipe'] as Map?)?['ingredients'] as List?)?.join(
                      ' · ',
                    ),
                    lines: 7,
                  ),
                ),
              ] else if (section == 'Events' || section == 'Star Paths') ...[
                line(
                  'Status',
                  eventStatus(data['event'] as Map? ?? {}, now),
                  lines: 1,
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: line(
                    'Dates',
                    (data['event'] as Map?)?['dates'],
                    lines: 4,
                  ),
                ),
              ] else
                Expanded(
                  child: Text(
                    categories,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: Colors.white54),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class FishingConditions extends StatelessWidget {
  final Map conditions;
  const FishingConditions({super.key, required this.conditions});
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fishing conditions',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          for (final field in {
            'Ripple color': 'ripples',
            'Weather': 'weather',
            'Time': 'time',
            'Location / zone': 'locations',
            'Other conditions / unlocks': 'conditions',
          }.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SelectableText(
                '${field.key}: ${fieldText(conditions[field.value], field.value == 'conditions' ? 'No extra conditions listed' : 'Unknown')}',
              ),
            ),
        ],
      ),
    ),
  );
}

class CompanionSchedule extends StatelessWidget {
  final Map<String, dynamic> data;
  final DateTime now;
  const CompanionSchedule({super.key, required this.data, required this.now});
  @override
  Widget build(BuildContext context) {
    final info = data['companion'] as Map? ?? {};
    final weekly = info['weekly'] as Map? ?? {};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              companionStatus(data, now),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            CompanionSourceBadge(info: info),
            const SizedBox(height: 10),
            Text(
              'How to obtain: ${fieldText((info['acquisition'] as Map?)?['description'])}',
            ),
            if (info['scheduled'] == true) ...[
              const SizedBox(height: 10),
              Text('Favorite: ${companionFood(data, 'Favorite')}'),
              const SizedBox(height: 8),
              Text('Liked: ${companionFood(data, 'Liked')}'),
              const SizedBox(height: 8),
              Text(
                'Approach: ${fieldText(info['feedingMethod'] ?? (data['fields'] as Map?)?['Feeding method:'])}',
              ),
              const SizedBox(height: 10),
              Text('Location: ${fieldText(info['location'])}'),
            ] else
              const Text('Unlocked without wild feeding.'),
            if (info['scheduled'] == true) ...[
              const SizedBox(height: 12),
              const Text(
                'Weekly appearance schedule · configured game time zone',
              ),
              for (final day in weekdays)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 100,
                        child: Text(
                          day,
                          style: TextStyle(
                            fontWeight: day == weekdays[now.weekday - 1]
                                ? FontWeight.bold
                                : null,
                          ),
                        ),
                      ),
                      Expanded(child: Text(fieldText(weekly[day]))),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
