import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_logcat_monitor/flutter_logcat_monitor.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:encrypt/encrypt.dart' as encrypt;

Future main() async {
  await dotenv.load(fileName: ".env");
  runApp(const LogcatApp());
}

class LogcatApp extends StatefulWidget {
  const LogcatApp({super.key});

  @override
  State<LogcatApp> createState() => _LogcatAppState();
}

class _LogcatAppState extends State<LogcatApp> {
  /// A buffer to store log messages.
  ///
  /// This `StringBuffer` is used to accumulate log messages
  /// throughout the application's lifecycle. It allows for
  /// efficient concatenation of strings and can be used to
  /// retrieve the entire log as a single string when needed.
  final StringBuffer _logBuffer = StringBuffer();

  /// An instance of `DeviceInfoPlugin` used to retrieve device information.
  ///
  /// This plugin provides APIs to access various device information such as
  /// hardware and software details. It supports both Android and iOS platforms.
  ///
  /// Example usage:
  /// ```dart
  /// DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
  /// if (Platform.isAndroid) {
  ///   AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
  ///   print('Running on ${androidInfo.model}');  // e.g. "Moto G (4)"
  /// } else if (Platform.isIOS) {
  ///   IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
  ///   print('Running on ${iosInfo.utsname.machine}');  // e.g. "iPhone7,1"
  /// }
  /// ```
  ///
  /// Make sure to add the necessary permissions in your `AndroidManifest.xml`
  /// and `Info.plist` files for accessing device information.
  DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

  /// Represents the currently selected value in a group of radio buttons or
  /// other selection widgets. The value is used to determine which option
  /// is currently selected. The default value is 0, indicating the first
  /// option is selected by default.
  int _groupValue = 0;

  /// A late final variable that holds an instance of `FlutterSecureStorage`.
  ///
  /// This variable is used to securely store and retrieve sensitive data
  /// such as user credentials, tokens, or any other confidential information.
  ///
  /// The `late` keyword indicates that this variable will be initialized
  /// at a later point before it is accessed, ensuring that it is not null
  /// when used.
  ///
  /// Example usage:
  /// ```dart
  /// secureStorage = FlutterSecureStorage();
  /// await secureStorage.write(key: 'token', value: 'your_token');
  /// String? token = await secureStorage.read(key: 'token');
  /// ```
  late final FlutterSecureStorage secureStorage;

  /// A list to store log messages as strings.
  ///
  /// This list is used to collect and manage log entries within the application.
  /// Each log entry is represented as a string and can be added to this list.
  ///
  /// Example usage:
  /// ```dart
  /// logList.add('This is a log message');
  /// print(logList); // Output: ['This is a log message']
  /// ```
  ///
  /// Note: Ensure that the list is properly managed to avoid excessive memory usage
  /// if the application generates a large number of log entries.
  List<String> logList = [];

  /// A Timer object that can be used to schedule a single callback or repeatedly
  /// execute a callback at a specified interval. The Timer can be null, indicating
  /// that it has not been initialized or has been canceled.
  Timer? _timer;

  /// Returns the Android-specific options for the application.
  ///
  /// This method creates an instance of [AndroidOptions] with the specified
  /// settings. Currently, it sets the `encryptedSharedPreferences` option to
  /// `true`, which means that the shared preferences will be encrypted for
  /// added security.
  ///
  /// Returns:
  ///   An [AndroidOptions] object with the configured settings.
  AndroidOptions _getAndroidOptions() => const AndroidOptions(
        encryptedSharedPreferences: true,
      );

  /// The URL of the worker service, retrieved from the environment variable 'BASE_URL'.
  /// If the environment variable is not set, an empty string is used as the default value.
  final String workerUrl = dotenv.env['BASE_URL'] ?? '';

  /// The key string used for encryption or decryption, retrieved from the environment variable 'keyStringKEY'.
  /// If the environment variable is not set, an empty string is used as the default value.
  final String _keyString = dotenv.env['keyStringKEY'] ?? '';

  /// The initialization vector (IV) string used for encryption or decryption, retrieved from the environment variable 'ivStringKEY'.
  /// If the environment variable is not set, an empty string is used as the default value.
  final String _ivString = dotenv.env['ivStringKEY'] ?? '';
  @override
  void initState() {
    super.initState();

    _startTimer();

    secureStorage = FlutterSecureStorage(aOptions: _getAndroidOptions());
    initPlatformState();
  }

  @override
  void dispose() {
    // Cancel the timer when the widget is disposed to avoid memory leaks
    _timer?.cancel();
    super.dispose();
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

  /// Serializes a list of logcat data into Syslog format.
  ///
  /// This function takes a list of logcat data lines, extracts relevant components
  /// such as date, time, log level, PID, and message, and formats them into Syslog
  /// entries. The Syslog entries are then joined into a single string separated by
  /// newlines.
  ///
  /// The priority of the Syslog entry is determined based on the log level:
  /// - "I" (Info) maps to priority 34
  /// - "E" (Error) maps to priority 3
  /// - "W" (Warning) maps to priority 5
  /// - Other levels default to priority 6 (Notice)
  ///
  /// The function also retrieves the device's hostname using the `deviceInfo` plugin.
  ///
  /// Example logcat line format:
  /// ```
  /// 12-12 14:33:11.027 I 1234 .logcat_flutte: Example log message
  /// ```
  ///
  /// Example Syslog entry format:
  /// ```
  /// <34>12-12 14:33:11.027 hostname .logcat_flutte[1234]: Example log message
  /// ```
  ///
  /// Parameters:
  /// - `logcatData`: A list of strings representing logcat data lines.
  ///
  /// Returns:
  /// A `Future<String>` that completes with the serialized Syslog entries as a single string.
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

  // This function encrypts the data using AES encryption
  /// Encrypts the given data using AES encryption algorithm.
  ///
  /// This function takes a plain text string as input and returns the encrypted
  /// data as a base64 encoded string. It uses a predefined key and initialization
  /// vector (IV) for the encryption process.
  ///
  /// The encryption is performed using the AES (Advanced Encryption Standard)
  /// algorithm in CBC (Cipher Block Chaining) mode.
  ///
  /// Parameters:
  /// - `data`: The plain text string to be encrypted.
  ///
  /// Returns:
  /// - A base64 encoded string representing the encrypted data.
  ///
  /// Example:
  /// ```dart
  /// String encryptedData = encryptData("mySensitiveData");
  /// print(encryptedData); // Outputs the encrypted data in base64 format
  /// ```
  ///
  /// Note:
  /// Ensure that `_keyString` and `_ivString` are properly defined and securely
  /// stored, as they are critical for the encryption and decryption process.
  String encryptData(String data) {
    final key = encrypt.Key.fromUtf8(_keyString);
    final iv = encrypt.IV.fromUtf8(_ivString);

    final encrypter = encrypt.Encrypter(encrypt.AES(key));

    // Encrypt the data
    final encrypted = encrypter.encrypt(data, iv: iv);

    return encrypted.base64; // Return the encrypted data as a base64 string
  }

  /// Uploads a list of logs to a remote server if there is an active internet connection.
  ///
  /// This function checks for various types of internet connectivity (WiFi, mobile, ethernet, VPN)
  /// before attempting to upload the logs. If a connection is available, it serializes the log list
  /// to a syslog format, converts it to a JSON string, encrypts the JSON string using AES encryption,
  /// and sends it to a remote server via an HTTP POST request. If the upload is successful, it logs
  /// a success message and clears the secure storage. If the upload fails or an error occurs, it logs
  /// the appropriate error message.
  ///
  /// Parameters:
  /// - `logList`: A list of logs to be uploaded.
  ///
  /// Returns:
  /// - A `Future<void>` that completes when the upload process is finished.
  Future<void> uploadLog(var logList) async {
    final List<ConnectivityResult> connectivityResult =
        await (Connectivity().checkConnectivity());
    if (connectivityResult.contains(ConnectivityResult.wifi) ||
        connectivityResult.contains(ConnectivityResult.mobile) ||
        connectivityResult.contains(ConnectivityResult.ethernet) ||
        connectivityResult.contains(ConnectivityResult.vpn)) {
      try {
        final sysLog = await serializeToSyslog(logList);

        // Convert the data to a JSON string
        String jsonData = json.encode(sysLog);

        // Encrypt the JSON string using AES
        String encryptedData = encryptData(jsonData);

        final response = await http.post(
          Uri.parse(workerUrl),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'encryptedData': encryptedData}),
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

  /// Starts a periodic timer that triggers every 15 seconds.
  ///
  /// The timer calls the `_generateLogData` method to generate log data
  /// and then uploads the logs using the `uploadLog` method.
  ///
  /// This function is useful for continuously uploading log data at regular intervals.
  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      // Call uploadLog every 15 seconds
      var logs = _generateLogData();
      uploadLog(logs);
    });
  }

  /// Generates a list of log data.
  ///
  /// This method returns the `logList` which contains the log data.
  /// It can be used to retrieve the current log entries.
  ///
  /// Returns:
  ///   A list of strings representing the log data.
  List<String> _generateLogData() {
    return logList;
  }

  /// Initializes the platform state for log monitoring.
  ///
  /// This method attempts to add a listener stream for log monitoring using
  /// the `FlutterLogcatMonitor` plugin. If the platform-specific code throws
  /// a `PlatformException`, it catches the exception and logs a failure message.
  /// After setting up the listener, it starts the log monitoring with a filter
  /// that captures all logs (`*.*`).
  ///
  /// This method is asynchronous and returns a [Future] that completes when
  /// the log monitoring has started.
  Future<void> initPlatformState() async {
    try {
      debugPrint('Attempting to add listen Stream of log.');
      FlutterLogcatMonitor.addListen(_listenStream);
    } on PlatformException {
      debugPrint('Failed to listen Stream of log.');
    }
    await FlutterLogcatMonitor.startMonitor("*.*");
  }

  /// Listens to a stream and performs actions based on the received value.
  ///
  /// This function writes the received value to secure storage with the current
  /// timestamp as the key. If the value is a string, it appends the value to
  /// the `_logBuffer`. Additionally, it reads all values from secure storage
  /// after a delay of 100 milliseconds and updates the `logList` with these values.
  ///
  /// - Parameter value: The value received from the stream, which can be of any type.
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

  /// Clears the log buffer and the logcat.
  ///
  /// This method performs the following actions:
  /// 1. Calls `FlutterLogcatMonitor.clearLogcat` to clear the logcat.
  /// 2. Waits for 100 milliseconds to ensure the logcat is cleared.
  /// 3. Updates the state by clearing the `_logBuffer` and adding a message
  ///    "log buffer cleared" to indicate the buffer has been cleared.
  ///
  /// This method is asynchronous and uses `setState` to update the UI after
  /// clearing the log buffer.
  void clearLog() async {
    FlutterLogcatMonitor.clearLogcat;
    await Future.delayed(const Duration(milliseconds: 100));
    setState(() {
      _logBuffer.clear();
      _logBuffer.writeln("log buffer cleared");
    });
  }
}
