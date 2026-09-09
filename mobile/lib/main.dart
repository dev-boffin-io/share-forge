// lib/main.dart

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';

import 'config.dart';
import 'server.dart';

void main() {
  FlutterForegroundTask.initCommunicationPort();
  runApp(const ShareForgeApp());
}

/// Keeps the process alive with a persistent notification while the server
/// is running. The server itself still runs on the main isolate (shelf
/// doesn't need a separate one) — this task only stops Android from
/// killing the app when the screen turns off.
Future<void> _initForegroundTask() async {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'share_forge_server',
      channelName: 'Share Forge server',
      channelDescription: 'Shows while the file server is running',
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

class ShareForgeApp extends StatelessWidget {
  const ShareForgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Share Forge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F1117),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF5C8AFF),
          surface: Color(0xFF1A1D27),
        ),
        textTheme: ThemeData.dark().textTheme.apply(fontSizeFactor: 1.15),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _folderPath;
  ShareForgeServer? _server;
  String? _localIp;
  bool _busy = false;

  Future<void> _pickFolder() async {
    // Requires "All files access" (MANAGE_EXTERNAL_STORAGE) so the picked
    // path is usable as a real filesystem path for dart:io — see README.
    final granted = await Permission.manageExternalStorage.request();
    if (!granted.isGranted) {
      _snack('Storage permission is required to pick a folder to share.');
      return;
    }
    final path = await FilePicker.platform.getDirectoryPath();
    if (path != null) setState(() => _folderPath = path);
  }

  @override
  void initState() {
    super.initState();
    _initForegroundTask();
  }

  Future<void> _toggleServer() async {
    if (_server != null && _server!.isRunning) {
      setState(() => _busy = true);
      await _server!.stop();
      await FlutterForegroundTask.stopService();
      setState(() {
        _server = null;
        _busy = false;
      });
      return;
    }

    if (_folderPath == null) {
      _snack('Pick a folder first.');
      return;
    }

    if (!await FlutterForegroundTask.checkNotificationPermission()
        .then((s) => s == NotificationPermission.granted)) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    setState(() => _busy = true);
    final server = ShareForgeServer(sharedDir: _folderPath!);
    await server.start(port: defaultPort);
    final ip = await getLocalIp();
    await FlutterForegroundTask.startService(
      notificationTitle: 'Share Forge running',
      notificationText: ip != null ? 'http://$ip:${server.port}' : 'Serving folder',
    );
    setState(() {
      _server = server;
      _localIp = ip;
      _busy = false;
    });
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final running = _server?.isRunning ?? false;
    final url = running && _localIp != null
        ? 'http://$_localIp:${_server!.port}'
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Share Forge')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_folderPath ?? 'No folder selected',
                style: const TextStyle(color: Color(0xFF7A7E94))),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _busy || running ? null : _pickFolder,
              child: const Text('Pick folder to share'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _toggleServer,
              style: FilledButton.styleFrom(
                backgroundColor: running ? Colors.red[400] : null,
              ),
              child: Text(running ? 'Stop server' : 'Start server'),
            ),
            const SizedBox(height: 24),
            if (url != null)
              SelectableText(url,
                  style: const TextStyle(
                      color: Color(0xFF3DBA74),
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
            if (running && _localIp == null)
              const Text('Started, but no Wi-Fi IP found — '
                  'check you\'re connected to a network.'),
          ],
        ),
      ),
    );
  }
}
