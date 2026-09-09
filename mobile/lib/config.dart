// lib/config.dart
// Mirrors core/config.py

import 'package:network_info_plus/network_info_plus.dart';

const int defaultPort = 8080; // 5000 clashes with AirPlay on some routers/phones
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
