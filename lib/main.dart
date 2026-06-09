import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

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
    final handwrittenTheme = GoogleFonts.caveatTextTheme();

    return MaterialApp(
      title: 'Weekly OATS Schedule',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2F7D32),
        scaffoldBackgroundColor: const Color(0xFFFFFDF4),
        textTheme: handwrittenTheme,
      ),
      home: const WeeklySchedulePage(),
    );
  }
}

enum EntryStatus {
  none,
  done,
  missed,
  unsure,
}

class ScheduleEntry {
  final String text;
  final int colorValue;
  final EntryStatus status;

  const ScheduleEntry({
    required this.text,
    required this.colorValue,
    required this.status,
  });

  ScheduleEntry copyWith({
    String? text,
    int? colorValue,
    EntryStatus? status,
  }) {
    return ScheduleEntry(
      text: text ?? this.text,
      colorValue: colorValue ?? this.colorValue,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'colorValue': colorValue,
      'status': status.name,
    };
  }

  factory ScheduleEntry.fromJson(Map<String, dynamic> json) {
    return ScheduleEntry(
      text: json['text'] as String? ?? '',
      colorValue: json['colorValue'] as int? ?? Colors.black.value,
      status: EntryStatus.values.firstWhere(
        (item) => item.name == json['status'],
        orElse: () => EntryStatus.none,
      ),
    );
  }
}

class WeekdayOption {
  final String label;
  final int weekday;

  const WeekdayOption(this.label, this.weekday);
}

class WeeklySchedulePage extends StatefulWidget {
  const WeeklySchedulePage({super.key});

  @override
  State<WeeklySchedulePage> createState() => _WeeklySchedulePageState();
}

class _WeeklySchedulePageState extends State<WeeklySchedulePage> {
  static const List<WeekdayOption> weekdayOptions = [
    WeekdayOption('MON', DateTime.monday),
    WeekdayOption('TUE', DateTime.tuesday),
    WeekdayOption('WED', DateTime.wednesday),
    WeekdayOption('THU', DateTime.thursday),
    WeekdayOption('FRI', DateTime.friday),
    WeekdayOption('SAT', DateTime.saturday),
    WeekdayOption('SUN', DateTime.sunday),
  ];

  final List<int> baseHours = List.generate(19, (index) => index + 6); // 6 → 24
  final Map<String, ScheduleEntry> entries = {};

  Timer? reviewTimer;

  bool use24HourFormat = true;
  int selectedStartWeekday = DateTime.sunday;
  int extraLateRows = 3;

  DateTime selectedWeekStart = DateTime.now();
  TimeOfDay reviewTime = const TimeOfDay(hour: 22, minute: 0);

  String team = '';
  String name = '';
  String lastAutoReviewDateKey = '';

  @override
  void initState() {
    super.initState();
    selectedWeekStart = _startOfWeek(DateTime.now(), selectedStartWeekday);
    _loadData();
    _startReviewTimer();
  }

  @override
  void dispose() {
    reviewTimer?.cancel();
    super.dispose();
  }

  TextStyle get _titleStyle => GoogleFonts.caveat(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      );

  TextStyle get _headerStyle => GoogleFonts.caveat(
        fontSize: 27,
        fontWeight: FontWeight.w700,
      );

  TextStyle get _cellStyle => GoogleFonts.caveat(
        fontSize: 21,
        fontWeight: FontWeight.w600,
      );

  DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

  DateTime _startOfWeek(DateTime date, int startWeekday) {
    final cleanDate = _dateOnly(date);
    final diff = (cleanDate.weekday - startWeekday) % 7;
    return cleanDate.subtract(Duration(days: diff));
  }

  DateTime _weekEnd() => selectedWeekStart.add(const Duration(days: 6));

  List<DateTime> _visibleDates() {
    return List.generate(7, (index) => selectedWeekStart.add(Duration(days: index)));
  }

  List<int> _allHours() {
    return [
      ...baseHours,
      ...List.generate(extraLateRows, (index) => 25 + index),
    ];
  }

  String _dateKey(DateTime date) {
    final cleanDate = _dateOnly(date);
    final y = cleanDate.year.toString().padLeft(4, '0');
    final m = cleanDate.month.toString().padLeft(2, '0');
    final d = cleanDate.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _cellKey(DateTime date, int hour) => '${_dateKey(date)}-$hour';

  String _shortDate(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final y = (date.year % 100).toString().padLeft(2, '0');
    return '$d.$m.$y';
  }

  String _dayLabel(DateTime date) {
    return weekdayOptions
        .firstWhere((item) => item.weekday == date.weekday)
        .label;
  }

  String _formatHour(int hour) {
    if (use24HourFormat) return hour.toString();

    final normalized = hour % 24 == 0 ? 24 : hour % 24;
    final isPm = normalized >= 12 && normalized < 24;
    final period = isPm ? 'PM' : 'AM';
    final displayHour = normalized % 12 == 0 ? 12 : normalized % 12;
    final plusOne = hour > 24 ? ' +1' : '';

    return '$displayHour $period$plusOne';
  }

  Color _statusBackground(EntryStatus status) {
    switch (status) {
      case EntryStatus.done:
        return const Color(0xFFC8E6C9);
      case EntryStatus.missed:
        return const Color(0xFFD7D7D7);
      case EntryStatus.unsure:
        return const Color(0xFFFFF2B8);
      case EntryStatus.none:
        return Colors.transparent;
    }
  }

  String _statusLabel(EntryStatus status) {
    switch (status) {
      case EntryStatus.done:
        return 'Done';
      case EntryStatus.missed:
        return 'Missed';
      case EntryStatus.unsure:
        return 'Not sure';
      case EntryStatus.none:
        return 'Not reviewed';
    }
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();

    final savedEntries = prefs.getString('entries');
    final savedWeekStart = prefs.getString('selectedWeekStart');

    if (savedEntries != null && savedEntries.trim().isNotEmpty) {
      final decoded = jsonDecode(savedEntries) as Map<String, dynamic>;
      entries
        ..clear()
        ..addAll(decoded.map(
          (key, value) => MapEntry(
            key,
            ScheduleEntry.fromJson(Map<String, dynamic>.from(value as Map)),
          ),
        ));
    }

    setState(() {
      use24HourFormat = prefs.getBool('use24HourFormat') ?? true;
      selectedStartWeekday = prefs.getInt('selectedStartWeekday') ?? DateTime.sunday;
      extraLateRows = prefs.getInt('extraLateRows') ?? 3;
      reviewTime = TimeOfDay(
        hour: prefs.getInt('reviewHour') ?? 22,
        minute: prefs.getInt('reviewMinute') ?? 0,
      );
      team = prefs.getString('team') ?? '';
      name = prefs.getString('name') ?? '';
      lastAutoReviewDateKey = prefs.getString('lastAutoReviewDateKey') ?? '';
      selectedWeekStart = savedWeekStart == null
          ? _startOfWeek(DateTime.now(), selectedStartWeekday)
          : _dateOnly(DateTime.parse(savedWeekStart));
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    final encodedEntries = entries.map((key, value) => MapEntry(key, value.toJson()));

    await prefs.setString('entries', jsonEncode(encodedEntries));
    await prefs.setBool('use24HourFormat', use24HourFormat);
    await prefs.setInt('selectedStartWeekday', selectedStartWeekday);
    await prefs.setInt('extraLateRows', extraLateRows);
    await prefs.setString('selectedWeekStart', selectedWeekStart.toIso8601String());
    await prefs.setInt('reviewHour', reviewTime.hour);
    await prefs.setInt('reviewMinute', reviewTime.minute);
    await prefs.setString('team', team);
    await prefs.setString('name', name);
    await prefs.setString('lastAutoReviewDateKey', lastAutoReviewDateKey);
  }

  void _startReviewTimer() {
    reviewTimer?.cancel();
    reviewTimer = Timer.periodic(const Duration(minutes: 1), (_) => _maybeAutoOpenReview());
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoOpenReview());
  }

  Future<void> _maybeAutoOpenReview() async {
    if (!mounted) return;

    final now = DateTime.now();
    final todayKey = _dateKey(now);
    final reviewDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      reviewTime.hour,
      reviewTime.minute,
    );

    final shouldReview = !now.isBefore(reviewDateTime) && lastAutoReviewDateKey != todayKey;
    if (!shouldReview) return;

    final hasTodayEntries = entries.keys.any((key) => key.startsWith('$todayKey-'));
    if (!hasTodayEntries) {
      lastAutoReviewDateKey = todayKey;
      await _saveData();
      return;
    }

    lastAutoReviewDateKey = todayKey;
    await _saveData();
    await _reviewDate(_dateOnly(now));
  }

  Future<void> _chooseReviewTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: reviewTime,
    );

    if (selected == null) return;

    setState(() => reviewTime = selected);
    await _saveData();
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
        title: Text(title, style: _titleStyle),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: GoogleFonts.caveat(fontSize: 28),
          decoration: InputDecoration(hintText: title),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == null) return;

    setState(() => onSaved(result));
    await _saveData();
  }

  Future<void> _editEntry(DateTime date, int hour) async {
    final cellKey = _cellKey(date, hour);
    final oldEntry = entries[cellKey] ??
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
                '${_dayLabel(date)} ${_shortDate(date)} - ${_formatHour(hour)}',
                style: _titleStyle,
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: textController,
                      autofocus: true,
                      maxLines: 3,
                      style: GoogleFonts.caveat(fontSize: 28, color: selectedColor),
                      decoration: const InputDecoration(
                        hintText: 'Write the appointment / task...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text('Ink color', style: _headerStyle),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final color in const [
                          Colors.black,
                          Colors.red,
                          Colors.blue,
                          Colors.green,
                          Colors.purple,
                          Colors.orange,
                          Colors.brown,
                          Colors.teal,
                        ])
                          _colorDot(
                            color: color,
                            selectedColor: selectedColor,
                            onTap: () => dialogSetState(() => selectedColor = color),
                          ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final custom = await _pickCustomColor(selectedColor);
                            if (custom != null) {
                              dialogSetState(() => selectedColor = custom);
                            }
                          },
                          icon: const Icon(Icons.palette_outlined),
                          label: const Text('Custom'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text('Review status', style: _headerStyle),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Not reviewed'),
                          selected: oldEntry.status == EntryStatus.none,
                          onSelected: (_) {},
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
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

  Widget _colorDot({
    required Color color,
    required Color selectedColor,
    required VoidCallback onTap,
  }) {
    final selected = color.value == selectedColor.value;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: selected ? 36 : 30,
        height: selected ? 36 : 30,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black, width: selected ? 2.2 : 0.8),
        ),
        child: selected ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
      ),
    );
  }

  Future<Color?> _pickCustomColor(Color initial) async {
    double red = initial.red.toDouble();
    double green = initial.green.toDouble();
    double blue = initial.blue.toDouble();

    return showDialog<Color>(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final current = Color.fromARGB(255, red.round(), green.round(), blue.round());

            Widget slider(String label, double value, ValueChanged<double> onChanged, Color activeColor) {
              return Row(
                children: [
                  SizedBox(width: 24, child: Text(label, style: const TextStyle(fontFamily: null))),
                  Expanded(
                    child: Slider(
                      value: value,
                      max: 255,
                      divisions: 255,
                      activeColor: activeColor,
                      label: value.round().toString(),
                      onChanged: onChanged,
                    ),
                  ),
                ],
              );
            }

            return AlertDialog(
              title: Text('Custom ink color', style: _titleStyle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: current,
                      border: Border.all(color: Colors.black),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  slider('R', red, (v) => setDialogState(() => red = v), Colors.red),
                  slider('G', green, (v) => setDialogState(() => green = v), Colors.green),
                  slider('B', blue, (v) => setDialogState(() => blue = v), Colors.blue),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(context, current), child: const Text('Use')),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _reviewToday() async {
    await _reviewDate(_dateOnly(DateTime.now()));
  }

  Future<void> _reviewDate(DateTime date) async {
    final targetKey = _dateKey(date);
    final dayEntries = entries.entries
        .where((entry) => entry.key.startsWith('$targetKey-'))
        .toList()
      ..sort((a, b) {
        final aHour = int.parse(a.key.split('-').last);
        final bHour = int.parse(b.key.split('-').last);
        return aHour.compareTo(bHour);
      });

    if (!mounted) return;

    if (dayEntries.isEmpty) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Daily Review', style: _titleStyle),
          content: Text('No planned items for ${_dayLabel(date)} ${_shortDate(date)}.'),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
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
              title: Text('${_dayLabel(date)} ${_shortDate(date)} Review', style: _titleStyle),
              content: SizedBox(
                width: math.min(MediaQuery.of(context).size.width * 0.9, 520),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: dayEntries.length,
                  itemBuilder: (context, index) {
                    final mapEntry = dayEntries[index];
                    final entryKey = mapEntry.key;
                    final entry = entries[entryKey]!;
                    final hour = int.parse(entryKey.split('-').last);

                    return Card(
                      color: _statusBackground(entry.status),
                      child: ListTile(
                        title: Text(
                          '${_formatHour(hour)} - ${entry.text}',
                          style: GoogleFonts.caveat(
                            fontSize: 25,
                            fontWeight: FontWeight.w700,
                            color: Color(entry.colorValue),
                          ),
                        ),
                        subtitle: Text(_statusLabel(entry.status)),
                        trailing: PopupMenuButton<EntryStatus>(
                          tooltip: 'Mark result',
                          onSelected: (status) async {
                            dialogSetState(() {
                              entries[entryKey] = entry.copyWith(status: status);
                            });
                            setState(() {});
                            await _saveData();
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: EntryStatus.done, child: Text('Done')),
                            PopupMenuItem(value: EntryStatus.missed, child: Text('Missed')),
                            PopupMenuItem(value: EntryStatus.unsure, child: Text('Not sure')),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              actions: [
                FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _goToCurrentWeek() async {
    setState(() {
      selectedWeekStart = _startOfWeek(DateTime.now(), selectedStartWeekday);
    });
    await _saveData();
  }

  Future<void> _changeStartWeekday(int value) async {
    setState(() {
      selectedStartWeekday = value;
      selectedWeekStart = _startOfWeek(selectedWeekStart, selectedStartWeekday);
    });
    await _saveData();
  }

  @override
  Widget build(BuildContext context) {
    final reviewLabel = reviewTime.format(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFDF4),
        surfaceTintColor: const Color(0xFFFFFDF4),
        title: Text('Weekly Report', style: _titleStyle),
        actions: [
          IconButton(
            tooltip: use24HourFormat ? 'Switch to 12h' : 'Switch to 24h',
            onPressed: () async {
              setState(() => use24HourFormat = !use24HourFormat);
              await _saveData();
            },
            icon: const Icon(Icons.access_time),
          ),
          TextButton(
            onPressed: () async {
              setState(() => use24HourFormat = !use24HourFormat);
              await _saveData();
            },
            child: Text(use24HourFormat ? '24h' : '12h'),
          ),
          TextButton.icon(
            onPressed: _chooseReviewTime,
            icon: const Icon(Icons.schedule),
            label: Text('Review: $reviewLabel'),
          ),
          TextButton.icon(
            onPressed: _reviewToday,
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Review Today'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          Expanded(
            child: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: _buildScheduleTable(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Previous week',
                onPressed: () async {
                  setState(() => selectedWeekStart = selectedWeekStart.subtract(const Duration(days: 7)));
                  await _saveData();
                },
                icon: const Icon(Icons.chevron_left),
              ),
              InkWell(
                onTap: _goToCurrentWeek,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.45),
                    border: Border.all(color: Colors.black, width: 1.2),
                  ),
                  child: Text(
                    '${_shortDate(selectedWeekStart)} ~ ${_shortDate(_weekEnd())}',
                    style: GoogleFonts.caveat(fontSize: 31, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next week',
                onPressed: () async {
                  setState(() => selectedWeekStart = selectedWeekStart.add(const Duration(days: 7)));
                  await _saveData();
                },
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Start day:', style: GoogleFonts.caveat(fontSize: 25, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: selectedStartWeekday,
                items: weekdayOptions
                    .map((item) => DropdownMenuItem<int>(
                          value: item.weekday,
                          child: Text(item.label, style: GoogleFonts.caveat(fontSize: 24)),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  _changeStartWeekday(value);
                },
              ),
            ],
          ),
          InkWell(
            onTap: () => _editHeaderField(
              title: 'TEAM',
              initialValue: team,
              onSaved: (value) => team = value,
            ),
            child: Text(
              'TEAM : ${team.isEmpty ? '__________' : team}',
              style: _headerStyle,
            ),
          ),
          InkWell(
            onTap: () => _editHeaderField(
              title: 'NAME',
              initialValue: name,
              onSaved: (value) => name = value,
            ),
            child: Text(
              'NAME : ${name.isEmpty ? '__________' : name}',
              style: _headerStyle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleTable() {
    final dates = _visibleDates();
    final hours = _allHours();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 1.5)),
          child: Column(
            children: [
              Row(
                children: [
                  _headerCell(''),
                  for (final date in dates)
                    _headerCell('${_dayLabel(date)}\n${date.day.toString().padLeft(2, '0')}'),
                ],
              ),
              for (final hour in hours)
                Row(
                  children: [
                    _timeCell(_formatHour(hour)),
                    for (final date in dates) _scheduleCell(date, hour),
                  ],
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  setState(() => extraLateRows++);
                  await _saveData();
                },
                icon: const Icon(Icons.add),
                label: Text('Add late row', style: GoogleFonts.caveat(fontSize: 24)),
              ),
              if (extraLateRows > 0)
                OutlinedButton.icon(
                  onPressed: () async {
                    setState(() => extraLateRows--);
                    await _saveData();
                  },
                  icon: const Icon(Icons.remove),
                  label: Text('Remove late row', style: GoogleFonts.caveat(fontSize: 24)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _headerCell(String text) {
    return Container(
      width: 122,
      height: 47,
      alignment: Alignment.center,
      decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 0.8)),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: _headerStyle.copyWith(height: 0.9),
      ),
    );
  }

  Widget _timeCell(String text) {
    return Container(
      width: 122,
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 0.8)),
      child: Text(text, style: _headerStyle),
    );
  }

  Widget _scheduleCell(DateTime date, int hour) {
    final key = _cellKey(date, hour);
    final entry = entries[key];

    return GestureDetector(
      onTap: () => _editEntry(date, hour),
      child: Container(
        width: 122,
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: entry == null ? Colors.transparent : _statusBackground(entry.status),
          border: Border.all(color: Colors.black, width: 0.8),
        ),
        child: Text(
          entry?.text ?? '',
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: _cellStyle.copyWith(color: entry == null ? Colors.black : Color(entry.colorValue)),
        ),
      ),
    );
  }
}
