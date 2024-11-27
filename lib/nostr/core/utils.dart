import 'dart:developer' as dev;

import 'package:dart_nostr/dart_nostr.dart';

import 'package:dart_nostr/nostr/dart_nostr.dart';

/// {@template nostr_client_utils}
/// General utils to be used in a whole [Nostr] instance.
/// {@endtemplate}
class NostrClientUtils {
  /// Whether logs are enabled or not.
  bool _isLogsEnabled = true;

  /// Disables logs.
  void disableLogs() {
    _isLogsEnabled = false;
  }

  /// Enables logs.
  void enableLogs() {
    _isLogsEnabled = true;
  }

  /// Logs a message, and an optional error.
  void log(String message, [Object? error]) {
    if (_isLogsEnabled) {
      print(
        message, /* 
        name: "Nostr${error != null ? "Error" : ""}",
        error: error, */
      );
      if (error != null) {
        print(error);
      }
    }
  }
}
