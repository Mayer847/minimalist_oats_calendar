import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const OatsScheduleApp());
}

class OatsScheduleApp extends StatelessWidget {
  const OatsScheduleApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(
      useMaterial3: true,
      colorSchemeSeed: const Color(0xFF2F7D32),
      scaffoldBackgroundColor: const Color(0xFFFFFDF4),
    );

    return MaterialApp(
      title: 'Weekly OATS Schedule',
      debugShowCheckedModeBanner: false,
      theme: baseTheme.copyWith(
        textTheme: GoogleFonts.caveatTextTheme(baseTheme.textTheme),
        inputDecorationTheme: InputDecorationTheme(
          hintStyle: GoogleFonts.caveat(fontSize: 26, color: Colors.black45, shadows: const []),
          labelStyle: GoogleFonts.caveat(fontSize: 24, color: Colors.black87, shadows: const []),
          floatingLabelStyle: GoogleFonts.caveat(fontSize: 24, color: Colors.black87, shadows: const []),
          border: const OutlineInputBorder(),
        ),
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
  final int durationMinutes;

  const ScheduleEntry({
    required this.text,
    required this.colorValue,
    required this.status,
    required this.durationMinutes,
  });

  ScheduleEntry copyWith({String? text, int? colorValue, EntryStatus? status, int? durationMinutes}) {
    return ScheduleEntry(
      text: text ?? this.text,
      colorValue: colorValue ?? this.colorValue,
      status: status ?? this.status,
      durationMinutes: durationMinutes ?? this.durationMinutes,
    );
  }

  Map<String, dynamic> toJson() => {
        'text': text,
        'colorValue': colorValue,
        'status': status.name,
        'durationMinutes': durationMinutes,
      };

  factory ScheduleEntry.fromJson(Map<String, dynamic> json) {
    return ScheduleEntry(
      text: json['text'] as String? ?? '',
      colorValue: json['colorValue'] as int? ?? Colors.black.value,
      status: EntryStatus.values.firstWhere(
        (item) => item.name == json['status'],
        orElse: () => EntryStatus.none,
      ),
      durationMinutes: json['durationMinutes'] as int? ?? 60,
    );
  }
}

class WeekdayOption {
  final String label;
  final int weekday;
  const WeekdayOption(this.label, this.weekday);
}

class UndoSnapshot {
  final Map<String, ScheduleEntry> entries;
  final int extraLateRows;
  final String label;
  const UndoSnapshot(this.entries, this.extraLateRows, this.label);
}

class EntryDragData {
  final DateTime sourceDate;
  final int sourceStartMinutes;
  final ScheduleEntry entry;
  const EntryDragData(this.sourceDate, this.sourceStartMinutes, this.entry);
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

  static const int startHour = 6;
  static const int slotMinutes = 30;
  static const double dayColumnWidth = 124;
  static const double timeColumnWidth = 92;
  static const double slotHeight = 28;
  static const double headerHeight = 48;

  final Map<String, ScheduleEntry> entries = {};
  final List<UndoSnapshot> undoStack = [];
  final GlobalKey scheduleExportKey = GlobalKey();

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

  TextStyle get _titleStyle => GoogleFonts.caveat(fontSize: 34, fontWeight: FontWeight.w700, shadows: const []);
  TextStyle get _headerStyle => GoogleFonts.caveat(fontSize: 27, fontWeight: FontWeight.w700, shadows: const []);
  TextStyle get _cellStyle => GoogleFonts.caveat(fontSize: 21, fontWeight: FontWeight.w600, shadows: const []);

  DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

  DateTime _startOfWeek(DateTime date, int startWeekday) {
    final cleanDate = _dateOnly(date);
    final diff = (cleanDate.weekday - startWeekday) % 7;
    return cleanDate.subtract(Duration(days: diff));
  }

  DateTime _weekEnd() => selectedWeekStart.add(const Duration(days: 6));
  List<DateTime> _visibleDates() => List.generate(7, (index) => selectedWeekStart.add(Duration(days: index)));

  int get _endExclusiveHour => 25 + extraLateRows;
  int get _totalSlots => ((_endExclusiveHour - startHour) * 60) ~/ slotMinutes;
  double get _bodyHeight => _totalSlots * slotHeight;
  List<int> _hourLabels() => List.generate((24 + extraLateRows) - startHour + 1, (index) => startHour + index);

  String _dateKey(DateTime date) {
    final clean = _dateOnly(date);
    final y = clean.year.toString().padLeft(4, '0');
    final m = clean.month.toString().padLeft(2, '0');
    final d = clean.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _entryKey(DateTime date, int startMinutes) => '${_dateKey(date)}-$startMinutes';
  int _minutesFromKey(String key) => int.parse(key.split('-').last);

  String _shortDate(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final y = (date.year % 100).toString().padLeft(2, '0');
    return '$d.$m.$y';
  }

  String _dayLabel(DateTime date) => weekdayOptions.firstWhere((item) => item.weekday == date.weekday).label;

  String _formatHourLabel(int hour) {
    if (use24HourFormat) return hour.toString();
    final normalized = hour % 24 == 0 ? 24 : hour % 24;
    final period = normalized >= 12 && normalized < 24 ? 'PM' : 'AM';
    final displayHour = normalized % 12 == 0 ? 12 : normalized % 12;
    final plusOne = hour > 24 ? ' +1' : '';
    return '$displayHour $period$plusOne';
  }

  String _formatSlotTime(int totalMinutes) {
    final hour = totalMinutes ~/ 60;
    final minute = totalMinutes % 60;
    final minuteText = minute.toString().padLeft(2, '0');
    if (use24HourFormat) return '$hour:$minuteText';

    final normalizedHour = hour % 24 == 0 ? 24 : hour % 24;
    final period = normalizedHour >= 12 && normalizedHour < 24 ? 'PM' : 'AM';
    final displayHour = normalizedHour % 12 == 0 ? 12 : normalizedHour % 12;
    final plusOne = hour >= 24 ? ' +1' : '';
    return '$displayHour:$minuteText $period$plusOne';
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
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
        return const Color(0xFFFFFDF4);
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

  void _rememberUndo(String label) {
    undoStack.add(UndoSnapshot(Map<String, ScheduleEntry>.from(entries), extraLateRows, label));
    if (undoStack.length > 25) undoStack.removeAt(0);
  }

  Future<void> _undo() async {
    if (undoStack.isEmpty) return;
    final snapshot = undoStack.removeLast();
    setState(() {
      entries
        ..clear()
        ..addAll(snapshot.entries);
      extraLateRows = snapshot.extraLateRows;
    });
    await _saveData();
  }

  void _ensureRowsFit(int maxEndMinutes) {
    final requiredEndHour = (maxEndMinutes / 60).ceil();
    final requiredExtraRows = math.max(3, requiredEndHour - 24);
    if (requiredExtraRows > extraLateRows) extraLateRows = requiredExtraRows;
  }

  void _resolveOverlapsForDate(String dateKey) {
    final dayEntries = entries.entries.where((entry) => entry.key.startsWith('$dateKey-')).toList()
      ..sort((a, b) => _minutesFromKey(a.key).compareTo(_minutesFromKey(b.key)));

    if (dayEntries.isEmpty) return;

    final rebuilt = <String, ScheduleEntry>{};
    var currentEnd = startHour * 60;

    for (final item in dayEntries) {
      var start = _minutesFromKey(item.key);
      if (start < currentEnd) {
        start = ((currentEnd + slotMinutes - 1) ~/ slotMinutes) * slotMinutes;
      }
      rebuilt['$dateKey-$start'] = item.value;
      currentEnd = start + item.value.durationMinutes;
    }

    entries.removeWhere((key, _) => key.startsWith('$dateKey-'));
    entries.addAll(rebuilt);
    _ensureRowsFit(currentEnd);
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEntries = prefs.getString('entries');
    final savedWeekStart = prefs.getString('selectedWeekStart');

    if (savedEntries != null && savedEntries.trim().isNotEmpty) {
      final decoded = jsonDecode(savedEntries) as Map<String, dynamic>;
      entries
        ..clear()
        ..addAll(decoded.map((key, value) => MapEntry(key, ScheduleEntry.fromJson(Map<String, dynamic>.from(value as Map)))));
    }

    setState(() {
      use24HourFormat = prefs.getBool('use24HourFormat') ?? true;
      selectedStartWeekday = prefs.getInt('selectedStartWeekday') ?? DateTime.sunday;
      extraLateRows = prefs.getInt('extraLateRows') ?? 3;
      reviewTime = TimeOfDay(hour: prefs.getInt('reviewHour') ?? 22, minute: prefs.getInt('reviewMinute') ?? 0);
      team = prefs.getString('team') ?? '';
      name = prefs.getString('name') ?? '';
      lastAutoReviewDateKey = prefs.getString('lastAutoReviewDateKey') ?? '';
      selectedWeekStart = savedWeekStart == null ? _startOfWeek(DateTime.now(), selectedStartWeekday) : _dateOnly(DateTime.parse(savedWeekStart));
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

  Map<String, dynamic> _backupJson() => {
        'version': 3,
        'exportedAt': DateTime.now().toIso8601String(),
        'settings': {
          'use24HourFormat': use24HourFormat,
          'selectedStartWeekday': selectedStartWeekday,
          'extraLateRows': extraLateRows,
          'selectedWeekStart': selectedWeekStart.toIso8601String(),
          'reviewHour': reviewTime.hour,
          'reviewMinute': reviewTime.minute,
          'team': team,
          'name': name,
        },
        'entries': entries.map((key, value) => MapEntry(key, value.toJson())),
      };

  void _downloadBytes(Uint8List bytes, String fileName, String mimeType) {
    final blob = html.Blob([bytes], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..download = fileName
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  Future<void> _exportJson() async {
    final pretty = const JsonEncoder.withIndent('  ').convert(_backupJson());
    _downloadBytes(Uint8List.fromList(utf8.encode(pretty)), 'oats_schedule_backup_${_shortDate(selectedWeekStart)}.json', 'application/json');
  }

  Future<void> _importJson() async {
    final upload = html.FileUploadInputElement()..accept = '.json,application/json';
    upload.click();
    await upload.onChange.first;
    final file = upload.files?.isEmpty == false ? upload.files!.first : null;
    if (file == null) return;

    final reader = html.FileReader();
    reader.readAsText(file);
    await reader.onLoadEnd.first;
    final text = reader.result as String?;
    if (text == null || text.trim().isEmpty) return;

    final decoded = jsonDecode(text) as Map<String, dynamic>;
    final settings = Map<String, dynamic>.from(decoded['settings'] as Map? ?? {});
    final rawEntries = Map<String, dynamic>.from(decoded['entries'] as Map? ?? decoded);

    _rememberUndo('Import JSON');
    setState(() {
      entries
        ..clear()
        ..addAll(rawEntries.map((key, value) => MapEntry(key, ScheduleEntry.fromJson(Map<String, dynamic>.from(value as Map)))));
      use24HourFormat = settings['use24HourFormat'] as bool? ?? use24HourFormat;
      selectedStartWeekday = settings['selectedStartWeekday'] as int? ?? selectedStartWeekday;
      extraLateRows = settings['extraLateRows'] as int? ?? extraLateRows;
      selectedWeekStart = settings['selectedWeekStart'] == null ? selectedWeekStart : _dateOnly(DateTime.parse(settings['selectedWeekStart'] as String));
      reviewTime = TimeOfDay(hour: settings['reviewHour'] as int? ?? reviewTime.hour, minute: settings['reviewMinute'] as int? ?? reviewTime.minute);
      team = settings['team'] as String? ?? team;
      name = settings['name'] as String? ?? name;
    });
    await _saveData();
  }

  Future<void> _exportPng() async {
    final context = scheduleExportKey.currentContext;
    if (context == null) return;
    final boundary = context.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;

    final image = await boundary.toImage(pixelRatio: 3);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;

    _downloadBytes(byteData.buffer.asUint8List(), 'oats_schedule_${_shortDate(selectedWeekStart)}_${_shortDate(_weekEnd())}.png', 'image/png');
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
    final reviewDateTime = DateTime(now.year, now.month, now.day, reviewTime.hour, reviewTime.minute);
    if (now.isBefore(reviewDateTime) || lastAutoReviewDateKey == todayKey) return;

    final hasTodayEntries = entries.keys.any((key) => key.startsWith('$todayKey-'));
    lastAutoReviewDateKey = todayKey;
    await _saveData();
    if (hasTodayEntries) await _reviewDate(_dateOnly(now));
  }

  Future<void> _chooseReviewTime() async {
    final selected = await showTimePicker(context: context, initialTime: reviewTime);
    if (selected == null) return;
    setState(() => reviewTime = selected);
    await _saveData();
  }

  Future<void> _chooseReviewDate() async {
    final picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (picked == null) return;
    await _reviewDate(_dateOnly(picked));
  }

  Future<void> _editHeaderField({required String title, required String initialValue, required ValueChanged<String> onSaved}) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title, style: _titleStyle),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: GoogleFonts.caveat(fontSize: 28, color: Colors.black, shadows: const []),
          decoration: InputDecoration(hintText: title, hintStyle: GoogleFonts.caveat(fontSize: 28, color: Colors.black45, shadows: const [])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (result == null) return;
    _rememberUndo('Edit $title');
    setState(() => onSaved(result));
    await _saveData();
  }

  Future<void> _editEntry(DateTime date, int startMinutes) async {
    final key = _entryKey(date, startMinutes);
    final oldEntry = entries[key] ?? ScheduleEntry(text: '', colorValue: Colors.black.value, status: EntryStatus.none, durationMinutes: 60);
    final textController = TextEditingController(text: oldEntry.text);
    Color selectedColor = Color(oldEntry.colorValue);
    int durationMinutes = oldEntry.durationMinutes;

    final result = await showDialog<ScheduleEntry?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${_dayLabel(date)} ${_shortDate(date)} - ${_formatSlotTime(startMinutes)}', style: _titleStyle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: textController,
                  autofocus: true,
                  maxLines: 3,
                  style: GoogleFonts.caveat(fontSize: 28, color: selectedColor, shadows: const []),
                  decoration: InputDecoration(
                    hintText: 'Write the appointment / task...',
                    hintStyle: GoogleFonts.caveat(fontSize: 27, color: Colors.black45, shadows: const []),
                  ),
                ),
                const SizedBox(height: 14),
                Text('Duration', style: _headerStyle),
                DropdownButton<int>(
                  value: durationMinutes,
                  items: const [30, 60, 90, 120, 150, 180, 240, 300, 360]
                      .map((m) => DropdownMenuItem<int>(value: m, child: Text(_formatDuration(m))))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setDialogState(() => durationMinutes = value);
                  },
                ),
                const SizedBox(height: 14),
                Text('Ink color', style: _headerStyle),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final color in const [Colors.black, Colors.red, Colors.blue, Colors.green, Colors.purple, Colors.orange, Colors.brown, Colors.teal])
                      _colorDot(color: color, selectedColor: selectedColor, onTap: () => setDialogState(() => selectedColor = color)),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final custom = await _pickCustomColor(selectedColor);
                        if (custom != null) setDialogState(() => selectedColor = custom);
                      },
                      icon: const Icon(Icons.palette_outlined),
                      label: const Text('Custom'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(context, ScheduleEntry(text: '', colorValue: selectedColor.value, status: EntryStatus.none, durationMinutes: durationMinutes)),
              child: const Text('Clear'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, oldEntry.copyWith(text: textController.text.trim(), colorValue: selectedColor.value, durationMinutes: durationMinutes)),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    _rememberUndo(result.text.isEmpty ? 'Clear item' : 'Edit item');
    setState(() {
      if (result.text.isEmpty) {
        entries.remove(key);
      } else {
        entries[key] = result;
        _resolveOverlapsForDate(_dateKey(date));
      }
    });
    await _saveData();
  }

  Widget _colorDot({required Color color, required Color selectedColor, required VoidCallback onTap}) {
    final selected = color.value == selectedColor.value;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: selected ? 36 : 30,
        height: selected ? 36 : 30,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.black, width: selected ? 2.2 : 0.8)),
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
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          final current = Color.fromARGB(255, red.round(), green.round(), blue.round());
          Widget slider(String label, double value, ValueChanged<double> onChanged, Color activeColor) => Row(
                children: [
                  SizedBox(width: 24, child: Text(label)),
                  Expanded(child: Slider(value: value, max: 255, divisions: 255, activeColor: activeColor, label: value.round().toString(), onChanged: onChanged)),
                ],
              );
          return AlertDialog(
            title: Text('Custom ink color', style: _titleStyle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 80, height: 80, decoration: BoxDecoration(color: current, border: Border.all(color: Colors.black), borderRadius: BorderRadius.circular(12))),
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
      ),
    );
  }

  Future<void> _reviewToday() async => _reviewDate(_dateOnly(DateTime.now()));

  Future<void> _setEntryStatus(String entryKey, ScheduleEntry entry, EntryStatus status, StateSetter dialogSetState) async {
    _rememberUndo('Review item');
    dialogSetState(() => entries[entryKey] = entry.copyWith(status: status));
    setState(() {});
    await _saveData();
  }

  Future<void> _reviewDate(DateTime date) async {
    final targetKey = _dateKey(date);
    final dayEntries = entries.entries.where((entry) => entry.key.startsWith('$targetKey-')).toList()
      ..sort((a, b) => _minutesFromKey(a.key).compareTo(_minutesFromKey(b.key)));

    if (!mounted) return;
    if (dayEntries.isEmpty) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Daily Review', style: _titleStyle),
          content: Text('No planned items for ${_dayLabel(date)} ${_shortDate(date)}.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, dialogSetState) => AlertDialog(
          title: Text('${_dayLabel(date)} ${_shortDate(date)} Review', style: _titleStyle),
          content: SizedBox(
            width: math.min(MediaQuery.of(context).size.width * 0.92, 680),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: dayEntries.length,
              itemBuilder: (context, index) {
                final entryKey = dayEntries[index].key;
                final entry = entries[entryKey]!;
                final start = _minutesFromKey(entryKey);
                return Card(
                  color: _statusBackground(entry.status),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 260,
                          child: Text(
                            '${_formatSlotTime(start)} • ${_formatDuration(entry.durationMinutes)}\n${entry.text}',
                            style: GoogleFonts.caveat(fontSize: 24, fontWeight: FontWeight.w700, color: Color(entry.colorValue), shadows: const []),
                          ),
                        ),
                        FilledButton(onPressed: () => _setEntryStatus(entryKey, entry, EntryStatus.done, dialogSetState), child: const Text('Done')),
                        FilledButton.tonal(onPressed: () => _setEntryStatus(entryKey, entry, EntryStatus.missed, dialogSetState), child: const Text('Missed')),
                        OutlinedButton(onPressed: () => _setEntryStatus(entryKey, entry, EntryStatus.unsure, dialogSetState), child: const Text('Not sure')),
                        Text(_statusLabel(entry.status)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
        ),
      ),
    );
  }

  Future<void> _goToCurrentWeek() async {
    setState(() => selectedWeekStart = _startOfWeek(DateTime.now(), selectedStartWeekday));
    await _saveData();
  }

  Future<void> _changeStartWeekday(int value) async {
    setState(() {
      selectedStartWeekday = value;
      selectedWeekStart = _startOfWeek(selectedWeekStart, selectedStartWeekday);
    });
    await _saveData();
  }

  int _slotFromLocalY(double y) {
    return (y / slotHeight).floor().clamp(0, _totalSlots - 1).toInt();
  }

  Future<void> _handleDrop(EntryDragData data, DateTime targetDate, int targetStartMinutes) async {
    final sourceKey = _entryKey(data.sourceDate, data.sourceStartMinutes);
    final targetKey = _entryKey(targetDate, targetStartMinutes);
    if (sourceKey == targetKey) return;

    _rememberUndo(_dateKey(data.sourceDate) == _dateKey(targetDate) ? 'Move item' : 'Copy item');
    setState(() {
      if (_dateKey(data.sourceDate) == _dateKey(targetDate)) entries.remove(sourceKey);
      entries[targetKey] = data.entry;
      _resolveOverlapsForDate(_dateKey(targetDate));
      if (_dateKey(data.sourceDate) == _dateKey(targetDate)) _resolveOverlapsForDate(_dateKey(data.sourceDate));
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
          TextButton.icon(
            onPressed: () async {
              setState(() => use24HourFormat = !use24HourFormat);
              await _saveData();
            },
            icon: const Icon(Icons.access_time),
            label: Text(use24HourFormat ? '24h' : '12h'),
          ),
          DropdownButton<int>(
            value: selectedStartWeekday,
            underline: const SizedBox.shrink(),
            items: weekdayOptions.map((item) => DropdownMenuItem<int>(value: item.weekday, child: Text(item.label, style: GoogleFonts.caveat(fontSize: 22)))).toList(),
            onChanged: (value) {
              if (value != null) _changeStartWeekday(value);
            },
          ),
          IconButton(tooltip: 'Undo', onPressed: undoStack.isEmpty ? null : _undo, icon: const Icon(Icons.undo)),
          PopupMenuButton<String>(
            tooltip: 'Export / Import',
            icon: const Icon(Icons.ios_share),
            onSelected: (value) {
              if (value == 'json_export') _exportJson();
              if (value == 'json_import') _importJson();
              if (value == 'png') _exportPng();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'json_export', child: Text('Export backup JSON')),
              PopupMenuItem(value: 'json_import', child: Text('Import backup JSON')),
              PopupMenuItem(value: 'png', child: Text('Download schedule PNG')),
            ],
          ),
          TextButton.icon(onPressed: _chooseReviewTime, icon: const Icon(Icons.schedule), label: Text('Auto: $reviewLabel')),
          TextButton.icon(onPressed: _reviewToday, icon: const Icon(Icons.today_outlined), label: const Text('Today')),
          TextButton.icon(onPressed: _chooseReviewDate, icon: const Icon(Icons.event_available_outlined), label: const Text('Review Day')),
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
                child: SingleChildScrollView(child: _buildScheduleTable()),
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
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.45), border: Border.all(color: Colors.black, width: 1.2)),
                  child: Text('${_shortDate(selectedWeekStart)} ~ ${_shortDate(_weekEnd())}', style: GoogleFonts.caveat(fontSize: 31, fontWeight: FontWeight.w700, shadows: const [])),
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
          InkWell(onTap: () => _editHeaderField(title: 'TEAM', initialValue: team, onSaved: (value) => team = value), child: Text('TEAM : ${team.isEmpty ? '__________' : team}', style: _headerStyle)),
          InkWell(onTap: () => _editHeaderField(title: 'NAME', initialValue: name, onSaved: (value) => name = value), child: Text('NAME : ${name.isEmpty ? '__________' : name}', style: _headerStyle)),
        ],
      ),
    );
  }

  Widget _buildScheduleTable() {
    final dates = _visibleDates();
    return RepaintBoundary(
      key: scheduleExportKey,
      child: ColoredBox(
        color: const Color(0xFFFFFDF4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 1.5)),
              child: Column(
                children: [
                  Row(children: [_headerCell('', width: timeColumnWidth), for (final date in dates) _dayHeaderCell(date)]),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [_timeColumn(), for (final date in dates) _dayColumn(date)]),
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
                      _rememberUndo('Add late row');
                      setState(() => extraLateRows++);
                      await _saveData();
                    },
                    icon: const Icon(Icons.add),
                    label: Text('Add late row', style: GoogleFonts.caveat(fontSize: 24, shadows: const [])),
                  ),
                  if (extraLateRows > 0)
                    OutlinedButton.icon(
                      onPressed: () async {
                        _rememberUndo('Remove late row');
                        setState(() => extraLateRows--);
                        await _saveData();
                      },
                      icon: const Icon(Icons.remove),
                      label: Text('Remove late row', style: GoogleFonts.caveat(fontSize: 24, shadows: const [])),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerCell(String text, {required double width}) {
    return Container(
      width: width,
      height: headerHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 0.8)),
      child: Text(text, textAlign: TextAlign.center, style: _headerStyle.copyWith(height: 0.9)),
    );
  }

  Widget _dayHeaderCell(DateTime date) {
    return GestureDetector(
      onTap: () => _reviewDate(date),
      child: Container(
        width: dayColumnWidth,
        height: headerHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 0.8)),
        child: Text('${_dayLabel(date)}\n${date.day.toString().padLeft(2, '0')}', textAlign: TextAlign.center, style: _headerStyle.copyWith(height: 0.9)),
      ),
    );
  }

  Widget _timeColumn() {
    return Container(
      width: timeColumnWidth,
      height: _bodyHeight,
      decoration: const BoxDecoration(border: Border(left: BorderSide(color: Colors.black, width: 0.8), right: BorderSide(color: Colors.black, width: 0.8))),
      child: CustomPaint(
        painter: RowDashPainter(totalSlots: _totalSlots, slotHeight: slotHeight, color: Colors.black54, showHourOnly: true),
        child: Stack(children: [
          for (final hour in _hourLabels())
            Positioned(top: (hour - startHour) * 2 * slotHeight, left: 0, right: 0, height: slotHeight * 2, child: Center(child: Text(_formatHourLabel(hour), style: _headerStyle))),
        ]),
      ),
    );
  }

  Widget _dayColumn(DateTime date) {
    final dateKey = _dateKey(date);
    final dayEntries = entries.entries.where((entry) => entry.key.startsWith('$dateKey-')).toList()
      ..sort((a, b) => _minutesFromKey(a.key).compareTo(_minutesFromKey(b.key)));

    return Builder(
      builder: (targetContext) => DragTarget<EntryDragData>(
        onAcceptWithDetails: (details) {
          final box = targetContext.findRenderObject() as RenderBox;
          final local = box.globalToLocal(details.offset);
          final slotIndex = _slotFromLocalY(local.dy);
          final startMinutes = startHour * 60 + (slotIndex * slotMinutes);
          _handleDrop(details.data, date, startMinutes);
        },
        builder: (context, candidateData, rejectedData) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final slotIndex = _slotFromLocalY(details.localPosition.dy);
            final startMinutes = startHour * 60 + (slotIndex * slotMinutes);
            _editEntry(date, startMinutes);
          },
          child: Container(
            width: dayColumnWidth,
            height: _bodyHeight,
            decoration: const BoxDecoration(border: Border(left: BorderSide(color: Colors.black, width: 0.8), right: BorderSide(color: Colors.black, width: 0.8))),
            child: CustomPaint(
              painter: RowDashPainter(totalSlots: _totalSlots, slotHeight: slotHeight, color: Colors.black38),
              child: Stack(clipBehavior: Clip.none, children: [
                if (candidateData.isNotEmpty) Positioned.fill(child: ColoredBox(color: Colors.greenAccent.withOpacity(0.08))),
                for (final mapEntry in dayEntries) _entryBlock(date, mapEntry.key, mapEntry.value),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _entryBlock(DateTime date, String key, ScheduleEntry entry) {
    final start = _minutesFromKey(key);
    final slotIndex = ((start - startHour * 60) / slotMinutes).round();
    final durationSlots = math.max(1, (entry.durationMinutes / slotMinutes).round());
    final top = slotIndex * slotHeight;
    final height = durationSlots * slotHeight;

    Widget block({double opacity = 1}) => Opacity(
          opacity: opacity,
          child: GestureDetector(
            onTap: () => _editEntry(date, start),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              decoration: BoxDecoration(color: _statusBackground(entry.status), border: Border.all(color: Color(entry.colorValue), width: 1.3), borderRadius: BorderRadius.circular(6)),
              child: Align(
                alignment: Alignment.topCenter,
                child: Text(entry.text, textAlign: TextAlign.center, maxLines: math.max(1, durationSlots), overflow: TextOverflow.ellipsis, style: _cellStyle.copyWith(color: Color(entry.colorValue))),
              ),
            ),
          ),
        );

    return Positioned(
      top: top,
      left: 4,
      right: 4,
      height: height,
      child: LongPressDraggable<EntryDragData>(
        data: EntryDragData(date, start, entry),
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(width: dayColumnWidth - 8, height: math.min(height, 90), child: block(opacity: 0.88)),
        ),
        childWhenDragging: block(opacity: 0.35),
        child: block(),
      ),
    );
  }
}

class RowDashPainter extends CustomPainter {
  final int totalSlots;
  final double slotHeight;
  final Color color;
  final bool showHourOnly;

  RowDashPainter({required this.totalSlots, required this.slotHeight, required this.color, this.showHourOnly = false});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.7;

    for (var slot = 1; slot < totalSlots; slot++) {
      if (showHourOnly && slot.isOdd) continue;
      final y = slot * slotHeight;
      final dashWidth = slot.isEven ? 11.0 : 5.5;
      final gap = slot.isEven ? 16.0 : 22.0;
      for (double x = 5; x < size.width - 5; x += dashWidth + gap) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + dashWidth, size.width - 5), y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant RowDashPainter oldDelegate) {
    return oldDelegate.totalSlots != totalSlots || oldDelegate.slotHeight != slotHeight || oldDelegate.color != color || oldDelegate.showHourOnly != showHourOnly;
  }
}
