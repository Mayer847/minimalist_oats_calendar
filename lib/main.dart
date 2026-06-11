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

import 'services/google_drive_sync_service.dart';

void main() => runApp(const OatsScheduleApp());

class OatsScheduleApp extends StatelessWidget {
  const OatsScheduleApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      colorSchemeSeed: const Color(0xFF2F7D32),
      scaffoldBackgroundColor: const Color(0xFFFFFDF4),
    );
    return MaterialApp(
      title: 'Weekly OATS Schedule',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        textTheme: GoogleFonts.caveatTextTheme(base.textTheme),
        inputDecorationTheme: InputDecorationTheme(
          hintStyle: GoogleFonts.caveat(
              fontSize: 26,
              height: 1.25,
              color: Colors.black45,
              shadows: const []),
          labelStyle: GoogleFonts.caveat(
              fontSize: 24,
              height: 1.25,
              color: Colors.black87,
              shadows: const []),
          floatingLabelStyle: GoogleFonts.caveat(
              fontSize: 24,
              height: 1.25,
              color: Colors.black87,
              shadows: const []),
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
  const ScheduleEntry(
      {required this.text,
      required this.colorValue,
      required this.status,
      required this.durationMinutes});

  ScheduleEntry copyWith(
          {String? text,
          int? colorValue,
          EntryStatus? status,
          int? durationMinutes}) =>
      ScheduleEntry(
        text: text ?? this.text,
        colorValue: colorValue ?? this.colorValue,
        status: status ?? this.status,
        durationMinutes: durationMinutes ?? this.durationMinutes,
      );

  Map<String, dynamic> toJson() => {
        'text': text,
        'colorValue': colorValue,
        'status': status.name,
        'durationMinutes': durationMinutes,
      };

  factory ScheduleEntry.fromJson(Map<String, dynamic> json) => ScheduleEntry(
        text: json['text'] as String? ?? '',
        colorValue: json['colorValue'] as int? ?? Colors.black.value,
        status: EntryStatus.values.firstWhere((e) => e.name == json['status'],
            orElse: () => EntryStatus.none),
        durationMinutes: json['durationMinutes'] as int? ?? 60,
      );
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

class RenderedSegment {
  final DateTime ownerDate;
  final int ownerStartMinutes;
  final DateTime columnDate;
  final int segmentStartMinutes;
  final int segmentDurationMinutes;
  final ScheduleEntry entry;
  final bool isContinuation;
  const RenderedSegment(
      {required this.ownerDate,
      required this.ownerStartMinutes,
      required this.columnDate,
      required this.segmentStartMinutes,
      required this.segmentDurationMinutes,
      required this.entry,
      required this.isContinuation});
}

class WeeklySchedulePage extends StatefulWidget {
  const WeeklySchedulePage({super.key});
  @override
  State<WeeklySchedulePage> createState() => _WeeklySchedulePageState();
}

class _WeeklySchedulePageState extends State<WeeklySchedulePage> {
  static const weekdayOptions = [
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
  static const int dayStartMinutes = startHour * 60;
  static const int nextDayStartMinutes =
      (24 + startHour) * 60; // 06:00 next day.
  static const double dayColumnWidth = 130;
  static const double timeColumnWidth = 96;
  static const double slotHeight =
      34; // bigger to prevent Caveat font trimming.
  static const double headerHeight = 58;

  final entries = <String, ScheduleEntry>{};
  final undoStack = <UndoSnapshot>[];
  final redoStack = <UndoSnapshot>[];
  final scheduleExportKey = GlobalKey();
  final driveSync = GoogleDriveSyncService();
  final cloudSyncDebouncer = SyncDebouncer(const Duration(seconds: 8));
  final horizontalController = ScrollController();
  final verticalController = ScrollController();

  Timer? reviewTimer;
  bool use24HourFormat = true;
  int selectedStartWeekday = DateTime.sunday;
  int extraLateRows = 6; // Up to 06:00 next day by default.
  DateTime selectedWeekStart = DateTime.now();
  TimeOfDay reviewTime = const TimeOfDay(hour: 22, minute: 0);
  String team = '';
  String name = '';
  String lastAutoReviewDateKey = '';
  bool cloudSyncEnabled = false;
  bool cloudSyncBusy = false;
  bool onboardingPromptShown = false;
  String cloudSyncStatus = 'Connect Drive';

  TextStyle get _titleStyle => GoogleFonts.caveat(
      fontSize: 34,
      height: 1.2,
      fontWeight: FontWeight.w700,
      shadows: const []);
  TextStyle get _headerStyle => GoogleFonts.caveat(
      fontSize: 27,
      height: 1.15,
      fontWeight: FontWeight.w700,
      shadows: const []);
  TextStyle get _cellStyle => GoogleFonts.caveat(
      fontSize: 21,
      height: 1.15,
      fontWeight: FontWeight.w600,
      shadows: const []);

  @override
  void initState() {
    super.initState();
    selectedWeekStart = _startOfWeek(DateTime.now(), selectedStartWeekday);
    _loadData();
    _startReviewTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initCloudSync();
      await _showFirstRunSyncPromptIfNeeded();
    });
  }

  @override
  void dispose() {
    reviewTimer?.cancel();
    cloudSyncDebouncer.dispose();
    horizontalController.dispose();
    verticalController.dispose();
    super.dispose();
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _startOfWeek(DateTime d, int startWeekday) => _dateOnly(d)
      .subtract(Duration(days: (_dateOnly(d).weekday - startWeekday) % 7));
  DateTime _weekEnd() => selectedWeekStart.add(const Duration(days: 6));
  List<DateTime> _visibleDates() =>
      List.generate(7, (i) => selectedWeekStart.add(Duration(days: i)));
  int get _endExclusiveHour => 24 + extraLateRows;
  int get _totalSlots => ((_endExclusiveHour - startHour) * 60) ~/ slotMinutes;
  double get _bodyHeight => _totalSlots * slotHeight;
  List<int> _hourLabels() =>
      List.generate((24 + extraLateRows) - startHour + 1, (i) => startHour + i);

  String _dateKey(DateTime date) {
    final d = _dateOnly(date);
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  DateTime? _dateFromKey(String key) {
    if (!_isDateEntryKey(key)) return null;
    final p = key.split('-');
    return DateTime.tryParse('${p[0]}-${p[1]}-${p[2]}');
  }

  bool _isDateEntryKey(String key) =>
      RegExp(r'^\d{4}-\d{2}-\d{2}-\d+$').hasMatch(key);

  String _entryKey(DateTime date, int startMinutes) =>
      '${_dateKey(date)}-$startMinutes';

  int _minutesFromKey(String key) {
    final last = key.split('-').last;
    return int.tryParse(last) ?? dayStartMinutes;
  }

  String _shortDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${(date.year % 100).toString().padLeft(2, '0')}';
  String _dayLabel(DateTime date) =>
      weekdayOptions.firstWhere((x) => x.weekday == date.weekday).label;

  String _formatHourLabel(int hour) {
    if (use24HourFormat) return hour.toString();
    final normalized = hour % 24 == 0 ? 24 : hour % 24;
    final period = normalized >= 12 && normalized < 24 ? 'PM' : 'AM';
    final display = normalized % 12 == 0 ? 12 : normalized % 12;
    return '$display $period${hour > 24 ? ' +1' : ''}';
  }

  String _formatSlotTime(int minutes) {
    final h = minutes ~/ 60;
    final m = (minutes % 60).toString().padLeft(2, '0');
    if (use24HourFormat) return '$h:$m';
    final normalized = h % 24 == 0 ? 24 : h % 24;
    final period = normalized >= 12 && normalized < 24 ? 'PM' : 'AM';
    final display = normalized % 12 == 0 ? 12 : normalized % 12;
    return '$display:$m $period${h >= 24 ? ' +1' : ''}';
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  Color _statusBackground(EntryStatus s) => switch (s) {
        EntryStatus.done => const Color(0xFFC8E6C9),
        EntryStatus.missed => const Color(0xFFD7D7D7),
        EntryStatus.unsure => const Color(0xFFFFF2B8),
        EntryStatus.none => const Color(0xFFFFFDF4),
      };

  String _statusLabel(EntryStatus s) => switch (s) {
        EntryStatus.done => 'Done',
        EntryStatus.missed => 'Missed',
        EntryStatus.unsure => 'Not sure',
        EntryStatus.none => 'Not reviewed',
      };

  void _rememberUndo(String label) {
    undoStack.add(UndoSnapshot(
        Map<String, ScheduleEntry>.from(entries), extraLateRows, label));
    redoStack.clear();
    if (undoStack.length > 50) undoStack.removeAt(0);
  }

  Future<void> _undo() async {
    if (undoStack.isEmpty) return;
    redoStack.add(UndoSnapshot(
        Map<String, ScheduleEntry>.from(entries), extraLateRows, 'Redo'));
    final snap = undoStack.removeLast();
    setState(() {
      entries
        ..clear()
        ..addAll(snap.entries);
      extraLateRows = snap.extraLateRows;
    });
    await _saveData();
  }

  Future<void> _redo() async {
    if (redoStack.isEmpty) return;
    undoStack.add(UndoSnapshot(
        Map<String, ScheduleEntry>.from(entries), extraLateRows, 'Undo redo'));
    final snap = redoStack.removeLast();
    setState(() {
      entries
        ..clear()
        ..addAll(snap.entries);
      extraLateRows = snap.extraLateRows;
    });
    await _saveData();
  }

  void _ensureRowsFit(int maxEndMinutes) {
    // Do not auto-expand the table when an item crosses 6 AM.
    // Overflow is rendered into the next day column instead.
    extraLateRows = math.max(extraLateRows, 6);
  }

  void _resolveOverlapsForDate(String dateKey) {
    final day = entries.entries
        .where((e) => e.key.startsWith('$dateKey-'))
        .toList()
      ..sort(
          (a, b) => _minutesFromKey(a.key).compareTo(_minutesFromKey(b.key)));
    if (day.isEmpty) return;
    final rebuilt = <String, ScheduleEntry>{};
    var currentEnd = dayStartMinutes;
    for (final item in day) {
      var start = _minutesFromKey(item.key);
      if (start < currentEnd)
        start = ((currentEnd + slotMinutes - 1) ~/ slotMinutes) * slotMinutes;
      rebuilt['$dateKey-$start'] = item.value;
      currentEnd = start + item.value.durationMinutes;
    }
    entries.removeWhere((k, _) => k.startsWith('$dateKey-'));
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
        ..addAll(Map.fromEntries(decoded.entries.where((item) => _isDateEntryKey(item.key)).map((item) => MapEntry(item.key, ScheduleEntry.fromJson(Map<String, dynamic>.from(item.value as Map))))));
    }
    setState(() {
      use24HourFormat = prefs.getBool('use24HourFormat') ?? true;
      selectedStartWeekday =
          prefs.getInt('selectedStartWeekday') ?? DateTime.sunday;
      extraLateRows = math.min(prefs.getInt('extraLateRows') ?? 6, 6);
      reviewTime = TimeOfDay(
          hour: prefs.getInt('reviewHour') ?? 22,
          minute: prefs.getInt('reviewMinute') ?? 0);
      team = prefs.getString('team') ?? '';
      name = prefs.getString('name') ?? '';
      lastAutoReviewDateKey = prefs.getString('lastAutoReviewDateKey') ?? '';
      onboardingPromptShown = prefs.getBool('onboardingPromptShown') ?? false;
      cloudSyncEnabled = false; // Access token is session-only; reconnect Drive each browser session.
      selectedWeekStart = savedWeekStart == null
          ? _startOfWeek(DateTime.now(), selectedStartWeekday)
          : _dateOnly(DateTime.parse(savedWeekStart));
    });
  }

  Future<void> _saveData({bool scheduleCloud = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'entries', jsonEncode(entries.map((k, v) => MapEntry(k, v.toJson()))));
    await prefs.setBool('use24HourFormat', use24HourFormat);
    await prefs.setInt('selectedStartWeekday', selectedStartWeekday);
    await prefs.setInt('extraLateRows', extraLateRows);
    await prefs.setString(
        'selectedWeekStart', selectedWeekStart.toIso8601String());
    await prefs.setInt('reviewHour', reviewTime.hour);
    await prefs.setInt('reviewMinute', reviewTime.minute);
    await prefs.setString('team', team);
    await prefs.setString('name', name);
    await prefs.setString('lastAutoReviewDateKey', lastAutoReviewDateKey);
    await prefs.setBool('onboardingPromptShown', onboardingPromptShown);
    await prefs.setBool('cloudSyncEnabled', cloudSyncEnabled);
    if (scheduleCloud) _scheduleCloudSync();
  }

  Map<String, dynamic> _backupJson() => {
        'version': 5,
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
        'entries': entries.map((k, v) => MapEntry(k, v.toJson())),
      };

  void _restoreFromBackupMap(Map<String, dynamic> backup) {
    final settings =
        Map<String, dynamic>.from(backup['settings'] as Map? ?? {});
    final rawEntries =
        Map<String, dynamic>.from(backup['entries'] as Map? ?? {});
    setState(() {
      entries
        ..clear()
        ..addAll(rawEntries.map((k, v) => MapEntry(
            k, ScheduleEntry.fromJson(Map<String, dynamic>.from(v as Map)))));
      use24HourFormat = settings['use24HourFormat'] as bool? ?? use24HourFormat;
      selectedStartWeekday =
          settings['selectedStartWeekday'] as int? ?? selectedStartWeekday;
      extraLateRows = settings['extraLateRows'] as int? ?? extraLateRows;
      if (settings['selectedWeekStart'] != null)
        selectedWeekStart =
            _dateOnly(DateTime.parse(settings['selectedWeekStart'] as String));
      reviewTime = TimeOfDay(
          hour: settings['reviewHour'] as int? ?? reviewTime.hour,
          minute: settings['reviewMinute'] as int? ?? reviewTime.minute);
      team = settings['team'] as String? ?? team;
      name = settings['name'] as String? ?? name;
    });
  }

  Future<void> _initCloudSync() async {
    if (!driveSync.isConfigured) {
      setState(() => cloudSyncStatus = 'Missing GOOGLE_CLIENT_ID');
      return;
    }
    try {
      await driveSync.initialize();
      if (mounted)
        setState(() =>
            cloudSyncStatus = cloudSyncEnabled ? 'Sync now' : 'Connect Drive');
    } catch (e) {
      if (mounted) setState(() => cloudSyncStatus = 'Drive init failed');
      debugPrint('Drive init failed: $e');
    }
  }

  Future<void> _showFirstRunSyncPromptIfNeeded() async {
    if (!mounted || onboardingPromptShown || cloudSyncEnabled) return;
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text('Set up backup', style: _titleStyle),
        content: const Text(
            'Connect Google Drive to automatically sync and restore your schedule on any device. Local-only mode stores data only in this browser/device and can be lost if browser data is cleared.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, 'local'),
              child: const Text('Use local only')),
          FilledButton(
              onPressed: () => Navigator.pop(context, 'drive'),
              child: const Text('Connect Google Drive')),
        ],
      ),
    );
    onboardingPromptShown = true;
    await _saveData(scheduleCloud: false);
    if (choice == 'drive') await _connectGoogleDrive();
  }

  Future<void> _connectGoogleDrive() async {
    if (cloudSyncBusy) return;
    setState(() {
      cloudSyncBusy = true;
      cloudSyncStatus = 'Connecting...';
    });
    try {
      await driveSync.initialize();
      await driveSync.connect();
      final cloudBackup = await driveSync.loadBackup();
      if (!mounted) return;
      if (cloudBackup == null) {
        await driveSync.saveBackup(_backupJson());
      } else {
        final choice = await showDialog<String>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text('Google Drive backup found', style: _titleStyle),
            content: const Text('Choose which schedule to use.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, 'local'),
                  child: const Text('Keep local and overwrite cloud')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, 'cloud'),
                  child: const Text('Restore cloud')),
            ],
          ),
        );
        if (choice == 'cloud') {
          _rememberUndo('Restore cloud');
          _restoreFromBackupMap(cloudBackup);
          await _saveData(scheduleCloud: false);
        } else {
          await driveSync.saveBackup(_backupJson());
        }
      }
      setState(() {
        cloudSyncEnabled = true;
        cloudSyncStatus = 'Synced';
      });
      await _saveData(scheduleCloud: false);
    } catch (e) {
      debugPrint('Google Drive sync error: $e');
      if (mounted) {
        setState(() => cloudSyncStatus = 'Sync error');
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Google Drive sync error: $e')));
      }
    } finally {
      if (mounted) setState(() => cloudSyncBusy = false);
    }
  }

  Future<void> _syncNow() async {
    if (!cloudSyncEnabled) {
      await _connectGoogleDrive();
      return;
    }
    if (cloudSyncBusy) return;
    setState(() {
      cloudSyncBusy = true;
      cloudSyncStatus = 'Syncing...';
    });
    try {
      await driveSync.saveBackup(_backupJson());
      if (mounted) setState(() => cloudSyncStatus = 'Synced');
    } catch (e) {
      if (mounted) {
        setState(() => cloudSyncStatus = 'Sync failed');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Manual sync failed: $e')));
      }
    } finally {
      if (mounted) setState(() => cloudSyncBusy = false);
    }
  }

  void _scheduleCloudSync() {
    if (!cloudSyncEnabled || cloudSyncBusy) return;
    cloudSyncDebouncer.run(() async {
      try {
        if (mounted) setState(() => cloudSyncStatus = 'Auto-syncing...');
        await driveSync.saveBackup(_backupJson());
        if (mounted) setState(() => cloudSyncStatus = 'Synced');
      } catch (e) {
        debugPrint('Auto-sync failed: $e');
        if (mounted) setState(() => cloudSyncStatus = 'Auto-sync failed');
      }
    });
  }

  Future<void> _exportJson() async {
    final bytes = Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(_backupJson())));
    _downloadBytes(
        bytes,
        'oats_schedule_backup_${_shortDate(selectedWeekStart)}.json',
        'application/json');
  }

  Future<void> _importJson() async {
    final upload = html.FileUploadInputElement()
      ..accept = '.json,application/json';
    upload.click();
    await upload.onChange.first;
    final file = upload.files?.isNotEmpty == true ? upload.files!.first : null;
    if (file == null) return;
    final reader = html.FileReader()..readAsText(file);
    await reader.onLoadEnd.first;
    final text = reader.result as String?;
    if (text == null) return;
    _rememberUndo('Import JSON');
    _restoreFromBackupMap(jsonDecode(text) as Map<String, dynamic>);
    await _saveData();
  }

  void _downloadBytes(Uint8List bytes, String fileName, String mime) {
    final blob = html.Blob([bytes], mime);
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..download = fileName
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  Future<void> _exportPng() async {
    final context = scheduleExportKey.currentContext;
    final boundary = context?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 3);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;
    _downloadBytes(
        byteData.buffer.asUint8List(),
        'oats_schedule_${_shortDate(selectedWeekStart)}_${_shortDate(_weekEnd())}.png',
        'image/png');
  }

  void _startReviewTimer() {
    reviewTimer?.cancel();
    reviewTimer = Timer.periodic(
        const Duration(minutes: 1), (_) => _maybeAutoOpenReview());
  }

  Future<void> _maybeAutoOpenReview() async {
    if (!mounted) return;
    final now = DateTime.now();
    final todayKey = _dateKey(now);
    final reviewDateTime = DateTime(
        now.year, now.month, now.day, reviewTime.hour, reviewTime.minute);
    if (now.isBefore(reviewDateTime) || lastAutoReviewDateKey == todayKey)
      return;
    lastAutoReviewDateKey = todayKey;
    await _saveData();
    if (entries.keys.any((k) => k.startsWith('$todayKey-')))
      await _reviewDate(_dateOnly(now));
  }

  Future<void> _chooseReviewTime() async {
    final selected =
        await showTimePicker(context: context, initialTime: reviewTime);
    if (selected == null) return;
    setState(() => reviewTime = selected);
    await _saveData();
  }

  Future<void> _chooseReviewDate() async {
    final picked = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2100));
    if (picked != null) await _reviewDate(_dateOnly(picked));
  }

  Future<void> _editHeaderField(
      String title, String initialValue, ValueChanged<String> onSaved) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title, style: _titleStyle),
        content: TextField(
            controller: controller,
            autofocus: true,
            style: GoogleFonts.caveat(
                fontSize: 28, height: 1.25, shadows: const [])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Save')),
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
    final old = entries[key] ??
        ScheduleEntry(
            text: '',
            colorValue: Colors.black.value,
            status: EntryStatus.none,
            durationMinutes: 60);
    final controller = TextEditingController(text: old.text);
    Color selectedColor = Color(old.colorValue);
    int durationMinutes = old.durationMinutes;

    final result = await showDialog<ScheduleEntry?>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
              '${_dayLabel(date)} ${_shortDate(date)} - ${_formatSlotTime(startMinutes)}',
              style: _titleStyle),
          content: SingleChildScrollView(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    maxLines: 3,
                    style: GoogleFonts.caveat(
                        fontSize: 28,
                        height: 1.25,
                        color: selectedColor,
                        shadows: const []),
                    decoration: InputDecoration(
                        hintText: 'Write the appointment / task...',
                        hintStyle: GoogleFonts.caveat(
                            fontSize: 27,
                            height: 1.25,
                            color: Colors.black45,
                            shadows: const [])),
                  ),
                  const SizedBox(height: 12),
                  Text('Duration', style: _headerStyle),
                  DropdownButton<int>(
                    value: durationMinutes,
                    items: const [
                      30,
                      60,
                      90,
                      120,
                      150,
                      180,
                      240,
                      300,
                      360,
                      480,
                      600,
                      720
                    ]
                        .map((m) => DropdownMenuItem(
                            value: m, child: Text(_formatDuration(m))))
                        .toList(),
                    onChanged: (v) => v == null
                        ? null
                        : setDialogState(() => durationMinutes = v),
                  ),
                  Text('Ink color', style: _headerStyle),
                  Wrap(spacing: 10, children: [
                    for (final color in const [
                      Colors.black,
                      Colors.red,
                      Colors.blue,
                      Colors.green,
                      Colors.purple,
                      Colors.orange,
                      Colors.brown,
                      Colors.teal
                    ])
                      GestureDetector(
                        onTap: () =>
                            setDialogState(() => selectedColor = color),
                        child: CircleAvatar(
                            backgroundColor: color,
                            child: selectedColor.value == color.value
                                ? const Icon(Icons.check, color: Colors.white)
                                : null),
                      ),
                  ]),
                ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(
                    context,
                    ScheduleEntry(
                        text: '',
                        colorValue: selectedColor.value,
                        status: EntryStatus.none,
                        durationMinutes: durationMinutes)),
                child: const Text('Clear')),
            FilledButton(
                onPressed: () => Navigator.pop(
                    context,
                    old.copyWith(
                        text: controller.text.trim(),
                        colorValue: selectedColor.value,
                        durationMinutes: durationMinutes)),
                child: const Text('Save')),
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

  Future<void> _reviewToday() async => _reviewDate(_dateOnly(DateTime.now()));

  Future<void> _setEntryStatus(String key, ScheduleEntry entry,
      EntryStatus status, StateSetter setDialogState) async {
    _rememberUndo('Review item');
    setDialogState(() => entries[key] = entry.copyWith(status: status));
    setState(() {});
    await _saveData();
  }

  Future<void> _reviewDate(DateTime date) async {
    final dk = _dateKey(date);
    final day = entries.entries.where((e) => e.key.startsWith('$dk-')).toList()
      ..sort(
          (a, b) => _minutesFromKey(a.key).compareTo(_minutesFromKey(b.key)));
    if (!mounted) return;
    if (day.isEmpty) {
      await showDialog(
          context: context,
          builder: (_) => AlertDialog(
                  title: Text('Daily Review', style: _titleStyle),
                  content: Text(
                      'No planned items for ${_dayLabel(date)} ${_shortDate(date)}.'),
                  actions: [
                    FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('OK'))
                  ]));
      return;
    }
    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${_dayLabel(date)} ${_shortDate(date)} Review',
              style: _titleStyle),
          content: SizedBox(
            width: math.min(MediaQuery.of(context).size.width * 0.92, 700),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: day.length,
              itemBuilder: (_, i) {
                final key = day[i].key;
                final entry = entries[key]!;
                final start = _minutesFromKey(key);
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
                                  '${_formatSlotTime(start)} â€¢ ${_formatDuration(entry.durationMinutes)}\n${entry.text}',
                                  style: GoogleFonts.caveat(
                                      fontSize: 24,
                                      height: 1.15,
                                      fontWeight: FontWeight.w700,
                                      color: Color(entry.colorValue),
                                      shadows: const []))),
                          FilledButton(
                              onPressed: () => _setEntryStatus(
                                  key, entry, EntryStatus.done, setDialogState),
                              child: const Text('Done')),
                          FilledButton.tonal(
                              onPressed: () => _setEntryStatus(key, entry,
                                  EntryStatus.missed, setDialogState),
                              child: const Text('Missed')),
                          OutlinedButton(
                              onPressed: () => _setEntryStatus(key, entry,
                                  EntryStatus.unsure, setDialogState),
                              child: const Text('Not sure')),
                          Text(_statusLabel(entry.status)),
                        ]),
                  ),
                );
              },
            ),
          ),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'))
          ],
        ),
      ),
    );
  }

  Future<void> _handleDrop(
      EntryDragData data, DateTime targetDate, int targetStartMinutes) async {
    final sourceKey = _entryKey(data.sourceDate, data.sourceStartMinutes);
    final targetKey = _entryKey(targetDate, targetStartMinutes);
    if (sourceKey == targetKey) return;
    _rememberUndo(_dateKey(data.sourceDate) == _dateKey(targetDate)
        ? 'Move item'
        : 'Copy item');
    setState(() {
      if (_dateKey(data.sourceDate) == _dateKey(targetDate))
        entries.remove(sourceKey);
      entries[targetKey] = data.entry;
      _resolveOverlapsForDate(_dateKey(targetDate));
    });
    await _saveData();
  }

  int _slotFromLocalY(double y) =>
      (y / slotHeight).floor().clamp(0, _totalSlots - 1).toInt();

  List<RenderedSegment> _segmentsForColumn(DateTime columnDate) {
    final columnStart =
        _dateOnly(columnDate).add(const Duration(minutes: dayStartMinutes));
    final columnEnd =
        _dateOnly(columnDate).add(const Duration(minutes: nextDayStartMinutes));
    final results = <RenderedSegment>[];

    for (final item in entries.entries) {
      if (!_isDateEntryKey(item.key)) continue;
      final ownerDate = _dateFromKey(item.key);
      if (ownerDate == null) continue;
      final ownerStartMinutes = _minutesFromKey(item.key);
      final itemStart =
          _dateOnly(ownerDate).add(Duration(minutes: ownerStartMinutes));
      final itemEnd =
          itemStart.add(Duration(minutes: item.value.durationMinutes));
      final overlapStart =
          itemStart.isAfter(columnStart) ? itemStart : columnStart;
      final overlapEnd = itemEnd.isBefore(columnEnd) ? itemEnd : columnEnd;
      if (!overlapEnd.isAfter(overlapStart)) continue;
      final segmentStartMinutes =
          dayStartMinutes + overlapStart.difference(columnStart).inMinutes;
      final segmentDuration = overlapEnd.difference(overlapStart).inMinutes;
      results.add(RenderedSegment(
        ownerDate: ownerDate,
        ownerStartMinutes: ownerStartMinutes,
        columnDate: columnDate,
        segmentStartMinutes: segmentStartMinutes,
        segmentDurationMinutes: segmentDuration,
        entry: item.value,
        isContinuation: !overlapStart.isAtSameMomentAs(itemStart),
      ));
    }
    results
        .sort((a, b) => a.segmentStartMinutes.compareTo(b.segmentStartMinutes));
    return results;
  }

  @override
  Widget build(BuildContext context) {
    final reviewLabel = reviewTime.format(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFDF4),
        surfaceTintColor: const Color(0xFFFFFDF4),
        title: Text('Weekly Report', style: _titleStyle),
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _buildTopScrollableBar(reviewLabel),
        _buildHeader(),
        Expanded(
            child: Scrollbar(
                controller: horizontalController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                    controller: horizontalController,
                    scrollDirection: Axis.horizontal,
                    child: Scrollbar(
                        controller: verticalController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                            controller: verticalController,
                            child: _buildScheduleTable()))))),
      ]),
    );
  }

  Widget _buildTopScrollableBar(String reviewLabel) {
    return Material(
      color: const Color(0xFFFFFDF4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(children: [
          TextButton.icon(
              onPressed: cloudSyncBusy ? null : _syncNow,
              icon: cloudSyncBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cloud_sync_outlined),
              label:
                  Text(cloudSyncEnabled ? cloudSyncStatus : 'Connect Drive')),
          const SizedBox(width: 6),
          OutlinedButton.icon(
              onPressed: cloudSyncEnabled && !cloudSyncBusy ? _syncNow : null,
              icon: const Icon(Icons.sync),
              label: const Text('Sync now')),
          const SizedBox(width: 6),
          TextButton.icon(
              onPressed: () async {
                setState(() => use24HourFormat = !use24HourFormat);
                await _saveData();
              },
              icon: const Icon(Icons.access_time),
              label: Text(use24HourFormat ? '24h' : '12h')),
          const SizedBox(width: 6),
          DropdownButton<int>(
              value: selectedStartWeekday,
              underline: const SizedBox.shrink(),
              items: weekdayOptions
                  .map((x) => DropdownMenuItem(
                      value: x.weekday,
                      child: Text(x.label,
                          style: GoogleFonts.caveat(fontSize: 22))))
                  .toList(),
              onChanged: (v) async {
                if (v == null) return;
                setState(() {
                  selectedStartWeekday = v;
                  selectedWeekStart =
                      _startOfWeek(selectedWeekStart, selectedStartWeekday);
                });
                await _saveData();
              }),
          IconButton(
              tooltip: 'Undo',
              onPressed: undoStack.isEmpty ? null : _undo,
              icon: const Icon(Icons.undo)),
          IconButton(
              tooltip: 'Redo',
              onPressed: redoStack.isEmpty ? null : _redo,
              icon: const Icon(Icons.redo)),
          PopupMenuButton<String>(
              icon: const Icon(Icons.ios_share),
              onSelected: (v) {
                if (v == 'json_export') _exportJson();
                if (v == 'json_import') _importJson();
                if (v == 'png') _exportPng();
              },
              itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: 'json_export',
                        child: Text('Export backup JSON')),
                    PopupMenuItem(
                        value: 'json_import',
                        child: Text('Import backup JSON')),
                    PopupMenuItem(
                        value: 'png', child: Text('Download schedule PNG'))
                  ]),
          TextButton.icon(
              onPressed: _chooseReviewTime,
              icon: const Icon(Icons.schedule),
              label: Text('Auto: $reviewLabel')),
          TextButton.icon(
              onPressed: _reviewToday,
              icon: const Icon(Icons.today_outlined),
              label: const Text('Today')),
          TextButton.icon(
              onPressed: _chooseReviewDate,
              icon: const Icon(Icons.event_available_outlined),
              label: const Text('Review Day')),
        ]),
      ),
    );
  }

  Widget _buildHeader() => Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
        child: Wrap(
            spacing: 16,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                    onPressed: () async {
                      setState(() => selectedWeekStart =
                          selectedWeekStart.subtract(const Duration(days: 7)));
                      await _saveData();
                    },
                    icon: const Icon(Icons.chevron_left)),
                InkWell(
                    onTap: () async {
                      setState(() => selectedWeekStart =
                          _startOfWeek(DateTime.now(), selectedStartWeekday));
                      await _saveData();
                    },
                    child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.45),
                            border:
                                Border.all(color: Colors.black, width: 1.2)),
                        child: Text(
                            '${_shortDate(selectedWeekStart)} ~ ${_shortDate(_weekEnd())}',
                            style: GoogleFonts.caveat(
                                fontSize: 30,
                                height: 1.15,
                                fontWeight: FontWeight.w700,
                                shadows: const [])))),
                IconButton(
                    onPressed: () async {
                      setState(() => selectedWeekStart =
                          selectedWeekStart.add(const Duration(days: 7)));
                      await _saveData();
                    },
                    icon: const Icon(Icons.chevron_right)),
              ]),
              InkWell(
                  onTap: () => _editHeaderField('TEAM', team, (v) => team = v),
                  child: Text('TEAM : ${team.isEmpty ? '__________' : team}',
                      style: _headerStyle)),
              InkWell(
                  onTap: () => _editHeaderField('NAME', name, (v) => name = v),
                  child: Text('NAME : ${name.isEmpty ? '__________' : name}',
                      style: _headerStyle)),
            ]),
      );

  Widget _buildScheduleTable() {
    final dates = _visibleDates();
    return RepaintBoundary(
      key: scheduleExportKey,
      child: ColoredBox(
        color: const Color(0xFFFFFDF4),
        child: Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              border: Border.all(color: Colors.black, width: 1.5)),
          child: Column(children: [
            Row(children: [
              _headerCell('', timeColumnWidth),
              for (final d in dates) _dayHeaderCell(d)
            ]),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _timeColumn(),
              for (final d in dates) _dayColumn(d)
            ]),
            Padding(
                padding: const EdgeInsets.all(8),
                child: Wrap(spacing: 10, children: [
                  OutlinedButton.icon(
                      onPressed: () async {
                        _rememberUndo('Add late row');
                        setState(() => extraLateRows++);
                        await _saveData();
                      },
                      icon: const Icon(Icons.add),
                      label: Text('Add late row',
                          style:
                              GoogleFonts.caveat(fontSize: 24, height: 1.1))),
                  if (extraLateRows > 0)
                    OutlinedButton.icon(
                        onPressed: () async {
                          _rememberUndo('Remove late row');
                          setState(() => extraLateRows--);
                          await _saveData();
                        },
                        icon: const Icon(Icons.remove),
                        label: Text('Remove late row',
                            style:
                                GoogleFonts.caveat(fontSize: 24, height: 1.1))),
                ])),
          ]),
        ),
      ),
    );
  }

  Widget _headerCell(String text, double width) => Container(
      width: width,
      height: headerHeight,
      alignment: Alignment.center,
      decoration:
          BoxDecoration(border: Border.all(color: Colors.black, width: 0.8)),
      child: Text(text,
          textAlign: TextAlign.center,
          style: _headerStyle.copyWith(height: 1.05)));

  Widget _dayHeaderCell(DateTime date) => GestureDetector(
      onTap: () => _reviewDate(date),
      child: Container(
          width: dayColumnWidth,
          height: headerHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              border: Border.all(color: Colors.black, width: 0.8)),
          child: Text(
              '${_dayLabel(date)}\n${date.day.toString().padLeft(2, '0')}',
              textAlign: TextAlign.center,
              style: _headerStyle.copyWith(height: 1.0))));

  Widget _timeColumn() => Container(
        width: timeColumnWidth,
        height: _bodyHeight,
        decoration: const BoxDecoration(
            border: Border(
                left: BorderSide(color: Colors.black, width: 0.8),
                right: BorderSide(color: Colors.black, width: 0.8))),
        child: CustomPaint(
            painter: RowDashPainter(
                totalSlots: _totalSlots,
                slotHeight: slotHeight,
                color: Colors.black54,
                showHourOnly: true),
            child: Stack(children: [
              for (final h in _hourLabels())
                Positioned(
                    top: (h - startHour) * 2 * slotHeight,
                    left: 0,
                    right: 0,
                    height: slotHeight * 2,
                    child: Center(
                        child: Text(_formatHourLabel(h), style: _headerStyle)))
            ])),
      );

  Widget _dayColumn(DateTime date) {
    final segments = _segmentsForColumn(date);
    return Builder(
        builder: (targetContext) => DragTarget<EntryDragData>(
              onAcceptWithDetails: (details) {
                final box = targetContext.findRenderObject() as RenderBox;
                final local = box.globalToLocal(details.offset);
                _handleDrop(details.data, date,
                    dayStartMinutes + _slotFromLocalY(local.dy) * slotMinutes);
              },
              builder: (context, candidates, rejected) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) => _editEntry(
                    date,
                    dayStartMinutes +
                        _slotFromLocalY(details.localPosition.dy) *
                            slotMinutes),
                child: Container(
                    width: dayColumnWidth,
                    height: _bodyHeight,
                    decoration: const BoxDecoration(
                        border: Border(
                            left: BorderSide(color: Colors.black, width: 0.8),
                            right:
                                BorderSide(color: Colors.black, width: 0.8))),
                    child: CustomPaint(
                        painter: RowDashPainter(
                            totalSlots: _totalSlots,
                            slotHeight: slotHeight,
                            color: Colors.black38),
                        child: Stack(clipBehavior: Clip.none, children: [
                          if (candidates.isNotEmpty)
                            Positioned.fill(
                                child: ColoredBox(
                                    color:
                                        Colors.greenAccent.withOpacity(0.08))),
                          for (final s in segments) _segmentBlock(s)
                        ]))),
              ),
            ));
  }

  Widget _segmentBlock(RenderedSegment segment) {
    final slotIndex =
        ((segment.segmentStartMinutes - dayStartMinutes) / slotMinutes).round();
    final durationSlots =
        math.max(1, (segment.segmentDurationMinutes / slotMinutes).ceil());
    final top = slotIndex * slotHeight;
    final height = durationSlots * slotHeight;
    final entry = segment.entry;
    Widget block([double opacity = 1]) => Opacity(
        opacity: opacity,
        child: GestureDetector(
            onTap: () =>
                _editEntry(segment.ownerDate, segment.ownerStartMinutes),
            child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                decoration: BoxDecoration(
                    color: _statusBackground(entry.status),
                    border:
                        Border.all(color: Color(entry.colorValue), width: 1.3),
                    borderRadius: BorderRadius.circular(6)),
                child: Align(
                    alignment: Alignment.topCenter,
                    child: Text(
                        '${segment.isContinuation ? 'â†³ ' : ''}${entry.text}',
                        textAlign: TextAlign.center,
                        maxLines: math.max(1, durationSlots),
                        overflow: TextOverflow.ellipsis,
                        style: _cellStyle.copyWith(
                            color: Color(entry.colorValue)))))));
    return Positioned(
        top: top,
        left: 4,
        right: 4,
        height: height,
        child: LongPressDraggable<EntryDragData>(
            data: EntryDragData(
                segment.ownerDate, segment.ownerStartMinutes, entry),
            feedback: Material(
                color: Colors.transparent,
                child: SizedBox(
                    width: dayColumnWidth - 8,
                    height: math.min(height, 100),
                    child: block(0.88))),
            childWhenDragging: block(0.35),
            child: block()));
  }
}

class RowDashPainter extends CustomPainter {
  final int totalSlots;
  final double slotHeight;
  final Color color;
  final bool showHourOnly;
  RowDashPainter(
      {required this.totalSlots,
      required this.slotHeight,
      required this.color,
      this.showHourOnly = false});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.7;
    for (var slot = 1; slot < totalSlots; slot++) {
      if (showHourOnly && slot.isOdd) continue;
      final y = slot * slotHeight;
      final dash = slot.isEven ? 11.0 : 5.5;
      final gap = slot.isEven ? 16.0 : 22.0;
      for (double x = 5; x < size.width - 5; x += dash + gap) {
        canvas.drawLine(
            Offset(x, y), Offset(math.min(x + dash, size.width - 5), y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant RowDashPainter old) =>
      old.totalSlots != totalSlots ||
      old.slotHeight != slotHeight ||
      old.color != color ||
      old.showHourOnly != showHourOnly;
}


