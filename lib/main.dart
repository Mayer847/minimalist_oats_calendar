import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const OatsScheduleApp());
}

class OatsScheduleApp extends StatelessWidget {
  const OatsScheduleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Weekly OATS Schedule',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.green,
        useMaterial3: true,
        textTheme: GoogleFonts.caveatTextTheme(),
      ),
      home: const WeeklySchedulePage(),
    );
  }
}

enum EntryStatus { none, done, missed, unsure }

class ScheduleEntry {
  final String text;
  final int colorValue;
  final EntryStatus status;

  ScheduleEntry({
    required this.text,
    required this.colorValue,
    required this.status,
  });

  ScheduleEntry copyWith({String? text, int? colorValue, EntryStatus? status}) {
    return ScheduleEntry(
      text: text ?? this.text,
      colorValue: colorValue ?? this.colorValue,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() {
    return {'text': text, 'colorValue': colorValue, 'status': status.name};
  }

  factory ScheduleEntry.fromJson(Map<String, dynamic> json) {
    return ScheduleEntry(
      text: json['text'] ?? '',
      colorValue: json['colorValue'] ?? Colors.black.value,
      status: EntryStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => EntryStatus.none,
      ),
    );
  }
}

class WeeklySchedulePage extends StatefulWidget {
  const WeeklySchedulePage({super.key});

  @override
  State<WeeklySchedulePage> createState() => _WeeklySchedulePageState();
}

class _WeeklySchedulePageState extends State<WeeklySchedulePage> {
  static const List<String> days = [
    'SUN',
    'MON',
    'TUE',
    'WED',
    'THU',
    'FRI',
    'SAT',
  ];

  static const List<int> hours = [
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20,
    21,
    22,
    23,
    24,
  ];

  final Map<String, ScheduleEntry> entries = {};

  bool use24HourFormat = true;
  TimeOfDay reviewTime = const TimeOfDay(hour: 22, minute: 0);

  String team = '';
  String name = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  String _key(String day, int hour) => '$day-$hour';

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();

    final savedEntries = prefs.getString('entries');
    final savedUse24 = prefs.getBool('use24HourFormat');
    final savedReviewHour = prefs.getInt('reviewHour');
    final savedReviewMinute = prefs.getInt('reviewMinute');
    final savedTeam = prefs.getString('team');
    final savedName = prefs.getString('name');

    if (savedEntries != null) {
      final decoded = jsonDecode(savedEntries) as Map<String, dynamic>;

      entries.clear();

      decoded.forEach((key, value) {
        entries[key] = ScheduleEntry.fromJson(value);
      });
    }

    setState(() {
      use24HourFormat = savedUse24 ?? true;
      reviewTime = TimeOfDay(
        hour: savedReviewHour ?? 22,
        minute: savedReviewMinute ?? 0,
      );
      team = savedTeam ?? '';
      name = savedName ?? '';
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();

    final encodedEntries = entries.map(
      (key, value) => MapEntry(key, value.toJson()),
    );

    await prefs.setString('entries', jsonEncode(encodedEntries));
    await prefs.setBool('use24HourFormat', use24HourFormat);
    await prefs.setInt('reviewHour', reviewTime.hour);
    await prefs.setInt('reviewMinute', reviewTime.minute);
    await prefs.setString('team', team);
    await prefs.setString('name', name);
  }

  String _formatHour(int hour) {
    if (use24HourFormat) {
      return hour.toString();
    }

    if (hour == 24) {
      return '12 AM';
    }

    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;

    return '$displayHour $period';
  }

  Color _statusBackground(EntryStatus status) {
    switch (status) {
      case EntryStatus.done:
        return Colors.green.withOpacity(0.25);
      case EntryStatus.missed:
        return Colors.grey.withOpacity(0.35);
      case EntryStatus.unsure:
        return Colors.amber.withOpacity(0.25);
      case EntryStatus.none:
        return Colors.transparent;
    }
  }

  Future<void> _editEntry(String day, int hour) async {
    final cellKey = _key(day, hour);
    final oldEntry =
        entries[cellKey] ??
        ScheduleEntry(
          text: '',
          colorValue: Colors.black.value,
          status: EntryStatus.none,
        );

    final textController = TextEditingController(text: oldEntry.text);
    Color selectedColor = Color(oldEntry.colorValue);

    final result = await showDialog<ScheduleEntry?>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, dialogSetState) {
            return AlertDialog(
              title: Text(
                '$day - ${_formatHour(hour)}',
                style: GoogleFonts.caveat(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: textController,
                    maxLines: 3,
                    style: GoogleFonts.caveat(fontSize: 26),
                    decoration: const InputDecoration(
                      hintText: 'Write your plan...',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    children: [
                      _colorDot(
                        Colors.black,
                        selectedColor,
                        () => dialogSetState(() {
                          selectedColor = Colors.black;
                        }),
                      ),
                      _colorDot(
                        Colors.red,
                        selectedColor,
                        () => dialogSetState(() {
                          selectedColor = Colors.red;
                        }),
                      ),
                      _colorDot(
                        Colors.blue,
                        selectedColor,
                        () => dialogSetState(() {
                          selectedColor = Colors.blue;
                        }),
                      ),
                      _colorDot(
                        Colors.green,
                        selectedColor,
                        () => dialogSetState(() {
                          selectedColor = Colors.green;
                        }),
                      ),
                      _colorDot(
                        Colors.purple,
                        selectedColor,
                        () => dialogSetState(() {
                          selectedColor = Colors.purple;
                        }),
                      ),
                      _colorDot(
                        Colors.orange,
                        selectedColor,
                        () => dialogSetState(() {
                          selectedColor = Colors.orange;
                        }),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(
                      context,
                      ScheduleEntry(
                        text: '',
                        colorValue: selectedColor.value,
                        status: EntryStatus.none,
                      ),
                    );
                  },
                  child: const Text('Clear'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(
                      context,
                      oldEntry.copyWith(
                        text: textController.text.trim(),
                        colorValue: selectedColor.value,
                      ),
                    );
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;

    setState(() {
      if (result.text.isEmpty) {
        entries.remove(cellKey);
      } else {
        entries[cellKey] = result;
      }
    });

    await _saveData();
  }

  Widget _colorDot(Color color, Color selectedColor, VoidCallback onTap) {
    final bool selected = color.value == selectedColor.value;

    return GestureDetector(
      onTap: onTap,
      child: CircleAvatar(
        radius: selected ? 17 : 14,
        backgroundColor: color,
        child: selected
            ? const Icon(Icons.check, color: Colors.white, size: 18)
            : null,
      ),
    );
  }

  Future<void> _chooseReviewTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: reviewTime,
    );

    if (selected == null) return;

    setState(() {
      reviewTime = selected;
    });

    await _saveData();
  }

  Future<void> _reviewToday() async {
    final now = DateTime.now();
    final todayIndex = now.weekday % 7;
    final today = days[todayIndex];

    final todayEntries =
        entries.entries
            .where((entry) => entry.key.startsWith('$today-'))
            .toList()
          ..sort((a, b) {
            final aHour = int.parse(a.key.split('-').last);
            final bHour = int.parse(b.key.split('-').last);
            return aHour.compareTo(bHour);
          });

    if (todayEntries.isEmpty) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Daily Review'),
          content: Text('No planned items for $today.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, dialogSetState) {
            return AlertDialog(
              title: Text(
                '$today Review',
                style: GoogleFonts.caveat(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: 420,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: todayEntries.length,
                  itemBuilder: (context, index) {
                    final mapEntry = todayEntries[index];
                    final entryKey = mapEntry.key;
                    final entry = entries[entryKey]!;
                    final hour = int.parse(entryKey.split('-').last);

                    return Card(
                      color: _statusBackground(entry.status),
                      child: ListTile(
                        title: Text(
                          '${_formatHour(hour)} - ${entry.text}',
                          style: GoogleFonts.caveat(
                            fontSize: 24,
                            color: Color(entry.colorValue),
                          ),
                        ),
                        subtitle: Text('Status: ${entry.status.name}'),
                        trailing: PopupMenuButton<EntryStatus>(
                          onSelected: (status) async {
                            dialogSetState(() {
                              entries[entryKey] = entry.copyWith(
                                status: status,
                              );
                            });

                            setState(() {});

                            await _saveData();
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: EntryStatus.done,
                              child: Text('Done'),
                            ),
                            PopupMenuItem(
                              value: EntryStatus.missed,
                              child: Text('Missed'),
                            ),
                            PopupMenuItem(
                              value: EntryStatus.unsure,
                              child: Text('Not sure'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _editHeaderField({
    required String title,
    required String initialValue,
    required ValueChanged<String> onSaved,
  }) async {
    final controller = TextEditingController(text: initialValue);

    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          style: GoogleFonts.caveat(fontSize: 26),
          decoration: InputDecoration(hintText: title),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == null) return;

    setState(() {
      onSaved(result);
    });

    await _saveData();
  }

  @override
  Widget build(BuildContext context) {
    final reviewLabel = reviewTime.format(context);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFDF4),
      appBar: AppBar(
        title: Text(
          'Weekly Report',
          style: GoogleFonts.caveat(fontSize: 34, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              setState(() {
                use24HourFormat = !use24HourFormat;
              });

              await _saveData();
            },
            icon: const Icon(Icons.access_time),
            label: Text(use24HourFormat ? '24h' : '12h'),
          ),
          TextButton.icon(
            onPressed: _chooseReviewTime,
            icon: const Icon(Icons.schedule),
            label: Text('Review: $reviewLabel'),
          ),
          TextButton.icon(
            onPressed: _reviewToday,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Review Today'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(child: _buildScheduleTable()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Row(
        children: [
          InkWell(
            onTap: () {
              _editHeaderField(
                title: 'TEAM',
                initialValue: team,
                onSaved: (value) => team = value,
              );
            },
            child: Text(
              'TEAM : ${team.isEmpty ? '__________' : team}',
              style: GoogleFonts.caveat(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 32),
          InkWell(
            onTap: () {
              _editHeaderField(
                title: 'NAME',
                initialValue: name,
                onSaved: (value) => name = value,
              );
            },
            child: Text(
              'NAME : ${name.isEmpty ? '__________' : name}',
              style: GoogleFonts.caveat(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleTable() {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black, width: 1.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _headerCell(''),
              for (final day in days) _headerCell(day),
            ],
          ),
          for (final hour in hours)
            Row(
              children: [
                _timeCell(_formatHour(hour)),
                for (final day in days) _scheduleCell(day, hour),
              ],
            ),
        ],
      ),
    );
  }

  Widget _headerCell(String text) {
    return Container(
      width: 120,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black, width: 0.8),
      ),
      child: Text(
        text,
        style: GoogleFonts.caveat(fontSize: 26, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _timeCell(String text) {
    return Container(
      width: 120,
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black, width: 0.8),
      ),
      child: Text(
        text,
        style: GoogleFonts.caveat(fontSize: 25, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _scheduleCell(String day, int hour) {
    final cellKey = _key(day, hour);
    final entry = entries[cellKey];

    return GestureDetector(
      onTap: () => _editEntry(day, hour),
      child: Container(
        width: 120,
        height: 58,
        padding: const EdgeInsets.all(4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: entry == null
              ? Colors.transparent
              : _statusBackground(entry.status),
          border: Border.all(color: Colors.black, width: 0.8),
        ),
        child: Text(
          entry?.text ?? '',
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.caveat(
            fontSize: 21,
            color: entry == null ? Colors.black : Color(entry.colorValue),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
