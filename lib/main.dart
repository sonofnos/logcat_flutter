import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_logcat_monitor/flutter_logcat_monitor.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const LogcatApp());
}

class LogcatApp extends StatefulWidget {
  const LogcatApp({super.key});

  @override
  State<LogcatApp> createState() => _LogcatAppState();
}

class _LogcatAppState extends State<LogcatApp> {
  final StringBuffer _logBuffer = StringBuffer();
  DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

  int _groupValue = 0;

  AndroidOptions _getAndroidOptions() => const AndroidOptions(
        encryptedSharedPreferences: true,
      );
  late final FlutterSecureStorage secureStorage;
  List<String> logList = [];

  @override
  void initState() {
    super.initState();
    _startTimer();

    secureStorage = FlutterSecureStorage(aOptions: _getAndroidOptions());
    initPlatformState();
  }

  Timer? _timer;

  final String workerUrl = 'https://logcat.christian1emeka.workers.dev';

  Future<String> serializeToSyslog(List<String> logcatData) async {
    AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
    final hostname = androidInfo;

    final List<String> syslogEntries = [];

    for (var line in logcatData) {
      // Split the log line by spaces to extract relevant components
      final parts = line.split(' ');

      if (parts.length > 7) {
        // Extracting the date and time
        final date = parts[0]; // Example: "12-12"
        final time = parts[1]; // Example: "14:33:11.027"

        // Constructing the timestamp (combining date and time)
        final logTimestamp = "$date $time";

        // Extracting the log level (e.g., "W" for Warning)
        final level = parts[2];

        // Extracting the PID (process ID)
        final pid = parts[3];

        // Extracting the tag (e.g., ".logcat_flutte")
        final tag = parts[4];

        // Joining the rest of the parts as the message
        final message = parts.sublist(5).join(' ');

        // Priority mapping (this could be adjusted depending on your needs)
        final priority = level == "I"
            ? 34
            : level == "E"
                ? 3
                : level == "W"
                    ? 5
                    : 6; // Default to "Notice" for unknown levels

        // Format the log entry into Syslog format
        final syslogEntry =
            '<$priority>$logTimestamp $hostname $tag[$pid]: $message';
        syslogEntries.add(syslogEntry);
      }
    }

    // Join all syslog entries with newline
    return syslogEntries.join('\n');
  }

  Future<void> uploadLog(var logList) async {
    final List<ConnectivityResult> connectivityResult =
        await (Connectivity().checkConnectivity());
    if (connectivityResult.contains(ConnectivityResult.wifi) ||
        connectivityResult.contains(ConnectivityResult.mobile) ||
        connectivityResult.contains(ConnectivityResult.ethernet) ||
        connectivityResult.contains(ConnectivityResult.vpn)) {
      try {
        final sysLog = await serializeToSyslog(logList);

        final response = await http.post(
          Uri.parse(workerUrl),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'data': sysLog, // Send the log list directly as JSON
          }),
        );

        if (response.statusCode == 200) {
          log('Log uploaded successfully');
          await secureStorage.deleteAll();
        } else {
          log('Failed to upload log: ${response.body}');
        }
      } catch (e) {
        log('Error uploading log: $e');
      }
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      // Call uploadLog every 15 seconds
      var logs = _generateLogData();
      uploadLog(logs);
    });
  }

  List<String> _generateLogData() {
    return logList;
  }

  @override
  void dispose() {
    // Cancel the timer when the widget is disposed to avoid memory leaks
    _timer?.cancel();
    super.dispose();
  }

  Future<void> initPlatformState() async {
    try {
      debugPrint('Attempting to add listen Stream of log.');
      FlutterLogcatMonitor.addListen(_listenStream);
    } on PlatformException {
      debugPrint('Failed to listen Stream of log.');
    }
    await FlutterLogcatMonitor.startMonitor("*.*");
  }

  void _listenStream(dynamic value) async {
    secureStorage.write(
        key: DateTime.now().millisecondsSinceEpoch.toString(), value: value);
    if (value is String) {
      if (mounted) {
        setState(() {
          _logBuffer.writeln(value);
        });
      } else {
        _logBuffer.writeln(value);
      }
    }

    Future.delayed(const Duration(milliseconds: 100), () async {
      var pref = await secureStorage.readAll();

      logList = pref.values.toList();

      log('log: ${pref.values.toList()}');
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Logcat App'),
        ),
        body: Column(
          children: [
            logBoxBuild(context),
            DropdownButton<int>(
              value: _groupValue,
              items: const [
                DropdownMenuItem(
                  value: 0,
                  child: Text("show all"),
                ),
                DropdownMenuItem(
                  value: 1,
                  child: Text("show debug (D) and below"),
                ),
                DropdownMenuItem(
                  value: 2,
                  child: Text("show info(I) and below"),
                ),
                DropdownMenuItem(
                  value: 3,
                  child: Text("show warning(W) and below"),
                ),
                DropdownMenuItem(
                  value: 4,
                  child: Text("show error(E) and below"),
                ),
                DropdownMenuItem(
                  value: 5,
                  child: Text("show fatal(F) and below"),
                ),
              ],
              onChanged: (int? value) async {
                setState(() {
                  _groupValue = value!;
                  _logBuffer.clear();
                });
                if (value == 0) {
                  await FlutterLogcatMonitor.startMonitor("*.*");
                } else if (value == 1) {
                  await FlutterLogcatMonitor.startMonitor(
                      "flutter:*,FlutterLogcatMonitorPlugin:*,*:D");
                } else if (value == 2) {
                  // warnings and above
                  await FlutterLogcatMonitor.startMonitor(
                      "flutter:*,FlutterLogcatMonitorPlugin:*,*:I");
                } else if (value == 3) {
                  await FlutterLogcatMonitor.startMonitor(
                      "flutter:*,FlutterLogcatMonitorPlugin:*,*:W");
                } else if (value == 4) {
                  await FlutterLogcatMonitor.startMonitor(
                      "flutter:*,FlutterLogcatMonitorPlugin:*,*:E");
                } else if (value == 5) {
                  await FlutterLogcatMonitor.startMonitor(
                      "flutter:*,FlutterLogcatMonitorPlugin:*,*:F");
                }
              },
            ),
            TextButton(
              onPressed: () async {
                clearLog();
              },
              style: TextButton.styleFrom(
                  elevation: 2, backgroundColor: Colors.amber[100]),
              child: const Text("Clear"),
            ),
          ],
        ),
      ),
    );
  }

  Widget logBoxBuild(BuildContext context) {
    return Expanded(
      child: Container(
        alignment: AlignmentDirectional.topStart,
        decoration: BoxDecoration(
          color: Colors.purple,
          border: Border.all(
            color: Colors.black,
            width: 1.0,
          ),
        ),
        child: SingleChildScrollView(
          reverse: true,
          scrollDirection: Axis.vertical,
          child: Text(
            _logBuffer.toString(),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.start,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14.0,
            ),
          ),
        ),
      ),
    );
  }

  void clearLog() async {
    FlutterLogcatMonitor.clearLogcat;
    await Future.delayed(const Duration(milliseconds: 100));
    setState(() {
      _logBuffer.clear();
      _logBuffer.writeln("log buffer cleared");
    });
  }
}
