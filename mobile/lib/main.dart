// lib/main.dart
// Mirrors gui/main_window.py — same "New Server" config + "Active Servers"
// list layout, live port check, Show all, multiple concurrent servers,
// Local/Network URL + Open in Browser per server, per-server log.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config.dart';
import 'server.dart';

void main() {
  FlutterForegroundTask.initCommunicationPort();
  runApp(const ShareForgeApp());
}

// Registered as the foreground service's callback so the notification's
// "Stop" button works even while the app is backgrounded. It only relays
// the press back to the main isolate — the server itself still runs there.
@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(_NotificationTaskHandler());
}

class _NotificationTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop_all') FlutterForegroundTask.sendDataToMain('stop_all');
  }
}

// ── theme (matches gui/main_window.py's dark palette) ──────────────────────
const _bg = Color(0xFF0F1117);
const _surface = Color(0xFF1A1D27);
const _border = Color(0xFF2A2D3A);
const _accent = Color(0xFF5C8AFF);
const _muted = Color(0xFF7A7E94);
const _green = Color(0xFF3DBA74);
const _red = Color(0xFFE05C5C);
const _orange = Color(0xFFE0A05C);

class ShareForgeApp extends StatelessWidget {
  const ShareForgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Share Forge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: _bg,
        colorScheme: const ColorScheme.dark(primary: _accent, surface: _surface),
        textTheme: ThemeData.dark().textTheme.apply(fontSizeFactor: 1.1),
      ),
      home: const HomePage(),
    );
  }
}

/// One running server + its own log, mirroring ServerCard in main_window.py.
class _RunningServer {
  final ShareForgeServer server;
  final String? localIp;
  final int port; // captured at start — server.port becomes null after stop()
  final List<String> log = [];

  _RunningServer({required this.server, required this.localIp})
      : port = server.port!;

  String get directory => server.sharedDir;
  bool get showAll => server.showAll;
  String get localUrl => 'http://127.0.0.1:$port';
  String? get networkUrl => localIp != null ? 'http://$localIp:$port' : null;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _folderPath;
  final _portController = TextEditingController(text: defaultPort.toString());
  bool _showAll = false;
  String _portStatus = '';
  Color _portStatusColor = _muted;
  bool _busy = false;

  final List<_RunningServer> _running = [];

  @override
  void initState() {
    super.initState();
    _initForegroundTask();
    _checkPortLive();
    _portController.addListener(_checkPortLive);
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);
    // Guard against an orphaned notification from a previous crash — on a
    // fresh launch _running is always empty, so nothing here means nothing
    // should still be foregrounded.
    FlutterForegroundTask.isRunningService.then((running) {
      if (running) FlutterForegroundTask.stopService();
    });
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    _portController.removeListener(_checkPortLive);
    _portController.dispose();
    super.dispose();
  }

  void _onReceiveTaskData(Object data) {
    if (data == 'stop_all') _stopAllServers();
  }

  Future<void> _stopAllServers() async {
    setState(() => _busy = true);
    for (final entry in List.of(_running)) {
      await entry.server.stop();
    }
    await FlutterForegroundTask.stopService();
    setState(() {
      _running.clear();
      _busy = false;
    });
    _checkPortLive();
  }

  Future<void> _initForegroundTask() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'share_forge_server',
        channelName: 'Share Forge server',
        channelDescription: 'Shows while a file server is running',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  // ─── port check ───────────────────────────────────────────────────────

  int? get _portValue => int.tryParse(_portController.text.trim());

  Future<void> _checkPortLive() async {
    final port = _portValue;
    if (port == null || port < 1024 || port > 65535) {
      setState(() {
        _portStatus = '✖ enter a port 1024–65535';
        _portStatusColor = _red;
      });
      return;
    }
    if (_running.any((s) => s.port == port)) {
      setState(() {
        _portStatus = '✖ already serving';
        _portStatusColor = _red;
      });
      return;
    }
    final free = await isPortFree(port);
    if (!mounted || _portValue != port) return; // stale response
    if (free) {
      setState(() {
        _portStatus = '✔ free';
        _portStatusColor = _green;
      });
    } else {
      final suggested = await findFreePort(port + 1);
      if (!mounted || _portValue != port) return;
      setState(() {
        _portStatus = '✖ in use → try $suggested';
        _portStatusColor = _red;
      });
    }
  }

  // ─── folder / server lifecycle ───────────────────────────────────────

  Future<void> _pickFolder() async {
    final granted = await Permission.manageExternalStorage.request();
    if (!granted.isGranted) {
      _snack('Storage permission is required to pick a folder to share.');
      return;
    }
    final path = await FilePicker.platform.getDirectoryPath();
    if (path != null) setState(() => _folderPath = path);
  }

  Future<void> _startServer() async {
    if (_folderPath == null) {
      _snack('Pick a folder first.');
      return;
    }
    var port = _portValue;
    if (port == null || port < 1024 || port > 65535) {
      _snack('Enter a valid port (1024–65535).');
      return;
    }
    if (_running.any((s) => s.port == port)) {
      _snack('Port $port is already serving.');
      return;
    }
    if (!await isPortFree(port)) {
      final suggested = await findFreePort(port + 1);
      final useIt = await _confirmPortInUse(port, suggested);
      if (useIt != true) return;
      port = suggested;
      _portController.text = port.toString();
    }

    if (!await FlutterForegroundTask.checkNotificationPermission()
        .then((s) => s == NotificationPermission.granted)) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    setState(() => _busy = true);
    final server = ShareForgeServer(sharedDir: _folderPath!, showAll: _showAll);
    await server.start(port: port);
    final ip = await getLocalIp();
    final entry = _RunningServer(server: server, localIp: ip)
      ..log.add('[+] :$port  ${server.sharedDir}');

    await _syncForegroundNotification([..._running, entry]);

    setState(() {
      _running.add(entry);
      _busy = false;
    });
    _portController.text = (await findFreePort(port + 1)).toString();
  }

  Future<bool?> _confirmPortInUse(int port, int suggested) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('Port In Use'),
        content: Text('Port $port is already in use.\nUse port $suggested instead?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _green),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
  }

  Future<void> _stopServer(_RunningServer entry) async {
    setState(() => _busy = true);
    await entry.server.stop();
    final remaining = _running.where((s) => s.port != entry.port).toList();
    await _syncForegroundNotification(remaining);
    setState(() {
      _running.remove(entry);
      _busy = false;
    });
    _checkPortLive();
  }

  Future<void> _syncForegroundNotification(List<_RunningServer> active) async {
    if (active.isEmpty) {
      await FlutterForegroundTask.stopService();
      return;
    }
    final ports = active.map((s) => ':${s.port}').join(', ');
    final text = '$ports running';
    if (!await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.startService(
        notificationTitle: 'Share Forge',
        notificationText: text,
        notificationButtons: const [NotificationButton(id: 'stop_all', text: 'Stop')],
        callback: _startCallback,
      );
    } else {
      await FlutterForegroundTask.updateService(notificationText: text);
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // ─── UI ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🔗 Share Forge'),
        backgroundColor: _bg,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildNewServerCard(),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _startServer,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1A3A1F),
                foregroundColor: _green,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('▶  Start Server', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 20),
            const Text('Active Servers', style: TextStyle(color: Color(0xFF9AA0C0), fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: _running.isEmpty
                  ? const Center(
                      child: Text('No active servers', style: TextStyle(color: Color(0xFF3A3D4A))))
                  : ListView.separated(
                      itemCount: _running.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _ServerCardWidget(
                        entry: _running[i],
                        onStop: () => _stopServer(_running[i]),
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            Text(
              _running.isEmpty
                  ? 'No active servers'
                  : '${_running.length} server${_running.length > 1 ? 's' : ''} running: '
                      '${_running.map((s) => ':${s.port}').join(', ')}',
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewServerCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('New Server', style: TextStyle(color: _muted)),
          const SizedBox(height: 10),
          Text(_folderPath ?? 'No folder selected',
              style: const TextStyle(color: _muted), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _pickFolder, child: const Text('Browse…')),
          const SizedBox(height: 14),
          Row(
            children: [
              const SizedBox(width: 60, child: Text('Port:')),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: _portController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(_portStatus, style: TextStyle(color: _portStatusColor)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          CheckboxListTile(
            value: _showAll,
            onChanged: (v) => setState(() => _showAll = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text(
              'Show all — no ignore rules (includes dotfiles, .git, node_modules, etc.)',
              style: TextStyle(fontSize: 12, color: _muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServerCardWidget extends StatelessWidget {
  final _RunningServer entry;
  final VoidCallback onStop;

  const _ServerCardWidget({required this.entry, required this.onStop});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(':${entry.port}',
                  style: const TextStyle(color: _accent, fontWeight: FontWeight.bold, fontSize: 18)),
              if (entry.showAll) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF6A4A2A)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('SHOW ALL', style: TextStyle(color: _orange, fontSize: 10)),
                ),
              ],
              const SizedBox(width: 8),
              Expanded(
                child: Text(entry.directory,
                    style: const TextStyle(color: Color(0xFF9AA0C0), fontSize: 12),
                    overflow: TextOverflow.ellipsis),
              ),
              TextButton(
                onPressed: onStop,
                style: TextButton.styleFrom(foregroundColor: _red),
                child: const Text('■  Stop'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  'Local: ${entry.localUrl}'
                  '${entry.localIp != null ? '    Network: ${entry.networkUrl}' : ''}',
                  style: const TextStyle(color: _green, fontSize: 12),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.open_in_browser, color: _accent, size: 20),
                tooltip: 'Open in browser',
                onPressed: () => launchUrl(Uri.parse(entry.localUrl)),
              ),
            ],
          ),
          if (entry.log.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(maxHeight: 60),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0C12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: SingleChildScrollView(
                child: Text(entry.log.join('\n'),
                    style: const TextStyle(color: Color(0xFF7A8090), fontSize: 11)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
