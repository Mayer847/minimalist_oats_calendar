import 'dart:async';
import 'dart:convert';
import 'dart:js_util' as js_util;

class GoogleDriveSyncService {
  static const String clientId = String.fromEnvironment('GOOGLE_CLIENT_ID');

  bool get isConfigured =>
      clientId.isNotEmpty && !clientId.contains('PASTE_YOUR_GOOGLE_CLIENT_ID_HERE');

  Future<void> initialize() async {
    if (!isConfigured) {
      throw StateError(
        'GOOGLE_CLIENT_ID is missing. Run/build with --dart-define=GOOGLE_CLIENT_ID=xxxxx.apps.googleusercontent.com',
      );
    }
    await _callPromise('oatsGoogleDriveInit', [clientId]);
  }

  Future<String?> connect() async {
    final result = await _callPromise('oatsGoogleDriveConnect', []);
    return result?.toString();
  }

  Future<void> signOut() async {
    await _callPromise('oatsGoogleDriveSignOut', []);
  }

  Future<Map<String, dynamic>?> loadBackup() async {
    final result = await _callPromise('oatsGoogleDriveLoadBackup', []);
    if (result == null) return null;
    if (result is String) return jsonDecode(result) as Map<String, dynamic>;

    final jsonObject = js_util.getProperty(js_util.globalThis, 'JSON');
    final jsonText = js_util.callMethod(jsonObject, 'stringify', [result]) as String;
    return jsonDecode(jsonText) as Map<String, dynamic>;
  }

  Future<void> saveBackup(Map<String, dynamic> backup) async {
    await _callPromise('oatsGoogleDriveSaveBackup', [jsonEncode(backup)]);
  }

  Future<String> getStatus() async {
    final result = await _callPromise('oatsGoogleDriveGetStatus', []);
    return result?.toString() ?? 'Disconnected';
  }

  Future<dynamic> _callPromise(String method, List<dynamic> args) async {
    final fn = js_util.getProperty(js_util.globalThis, method);
    if (fn == null) {
      throw StateError('$method is not loaded. Check web/google_drive_sync.js and web/index.html.');
    }
    final promise = js_util.callMethod(js_util.globalThis, method, args);
    return js_util.promiseToFuture(promise);
  }
}

class SyncDebouncer {
  SyncDebouncer(this.delay);
  final Duration delay;
  Timer? _timer;

  void run(Future<void> Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, () async => action());
  }

  void dispose() => _timer?.cancel();
}
