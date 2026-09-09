// lib/config.dart
// Mirrors core/config.py

import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';

const int defaultPort = 5000; // matches core/config.py DEFAULT_PORT
const String defaultHost = '0.0.0.0';

const Set<String> ignoredDirs = {
  '.venv', '.win_venv', '__pycache__', '.git', '.idea', 'node_modules',
};

/// Wi-Fi IPv4 of the phone, for showing the user a URL to open on other
/// devices. Falls back to null if not on Wi-Fi / unavailable — the UI
/// should tell the user to check they're on the same network.
Future<String?> getLocalIp() async {
  try {
    final info = NetworkInfo();
    return await info.getWifiIP();
  } catch (_) {
    return null;
  }
}

/// Mirrors core.config.is_port_free — tries to bind and immediately
/// releases. Not atomic (something else could grab it before we actually
/// start the server), same caveat as the desktop version.
Future<bool> isPortFree(int port, {String host = '0.0.0.0'}) async {
  try {
    final socket = await ServerSocket.bind(host, port, shared: false);
    await socket.close();
    return true;
  } catch (_) {
    return false;
  }
}

/// Mirrors core.config.find_free_port — first free port at or after
/// [start].
Future<int> findFreePort(int start, {String host = '0.0.0.0'}) async {
  var port = start;
  while (port < 65535) {
    if (await isPortFree(port, host: host)) return port;
    port++;
  }
  return start;
}
