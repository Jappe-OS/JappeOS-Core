//  JappeOS-Core, The core of JappeOS, runs on Linux.
//  Copyright (C) 2023  Jappe02
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as
//  published by the Free Software Foundation, either version 3 of the
//  License, or (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.

// ignore_for_file: constant_identifier_names

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:jappeos_messaging/jappeos_messaging.dart';

/// Core process name
const String PRCSS_CORE_THIS = "jappeos_core";

/// Login app process name
const String PRCSS_LOGIN = "login/jappeos_login";

/// Desktop app process name
const String PRCSS_DESKTOP = "desktop/jappeos_desktop";

/// Crash handler app process name
const String PRCSS_CRASH_HANDLE = "crh/jappeos_crh";

/// A list of processes
const List<String> PRCSS = [
  PRCSS_CORE_THIS,
  PRCSS_LOGIN,
  PRCSS_DESKTOP,
  PRCSS_CRASH_HANDLE
];

// Whether logged in or not
bool _isLoggedIn = false;

// Startup
bool _shouldQuit = false;
Future<void> main(List<String> arguments) async {
  if (await _Core.isAppRunning(0)) {
    print("Already running! Exiting...");
    exit(0);
  }

  // Application startup process;

  _Core.runProcess(1);

  JappeOSMessaging.init(8888);

  JappeOSMessaging.receive.subscribe((args) {
    switch (args!.value1.name) {
      case "login":
        {
          _Core.login(args.value1.args["u"] ?? "", args.value1.args["p"] ?? "");
          break;
        }
      case "logout":
        {
          _Core.logout();
          break;
        }
      case "logged-in":
        {
          JappeOSMessaging.send(Message("logged-in", {
            "id": args.value1.args["id"] ?? "0",
            "v": _Core.isLoggedIn().toString()
          }), args.value2.remotePort); // TODO Send target
          break;
        }
      case "shutdown":
        {
          _shouldQuit = true;
          break;
        }
    }
  });

  // Loop to keep app running;

  while (!_shouldQuit) {
    await Future.delayed(Duration(milliseconds: 10));
  }

  // Cleanup functions below;

  JappeOSMessaging.clean();

  for (int i = 0; i < PRCSS.length; i++) {
    _Core.killProcess(i);
  }

  exit(0);
}

/// Class that contains basic functions for this app. Does not contain any data.
class _Core {
  /// Check if a JappeOS process is running, returns false if not.
  static Future<bool> isAppRunning(int i) async {
    final result = await Process.run('pgrep', [PRCSS[i]]);
    final output = result.stdout as String;
    final processIds = output.trim().split('\n');
    return processIds.isNotEmpty;
  }

  /// Runs a JappeOS process.
  static Future<void> runProcess(int i, [List<String>? args]) async {
    final receivePort = ReceivePort();

    // Spawn a new isolate
    await Isolate.spawn(_processRunner, {
      'index': i,
      'args': args,
      'sendPort': receivePort.sendPort,
    });

    // Listen for messages from the isolate
    await for (final message in receivePort) {
      if (message is Map && message.containsKey('result')) {
        final result = message['result'];
        print("Process finished: ${PRCSS[i]} :: $result");

        // Handle crash for login or dekstop process if exit code is not 0 (success).
        if (result.exitCode != 0) {
          // Login Crash
          if (i == 1) {
            handleCrash(false, result.exitCode);
          }
          // Desktop Crash
          else if (i == 2) {
            handleCrash(true, result.exitCode);
          }
        }
      }
    }
  }

  /// Handle JappeOS process run isolate.
  static void _processRunner(Map<String, dynamic> data) async {
    final int index = data['index'];
    final List<String>? args = data['args'];
    final SendPort sendPort = data['sendPort'];

    for (int j = 0; j < PRCSS.length; j++) {
      if (j != index) {
        killProcess(index);
      }
    }

    print("Starting process: ${PRCSS[index]}");
    final result = await Process.run(PRCSS[index], args ?? []);
    sendPort.send({'result': result});
  }

  /// Kills a JappeOS process.
  static Future<void> killProcess(int i) async {
    final pgrepResult = await Process.run('pgrep', [PRCSS[i]]);
    final processIds = (pgrepResult.stdout as String).trim().split('\n');

    for (final pid in processIds) {
      await Process.run('pkill', ['-TERM', '-P', pid]);
      print("Process killed: ${PRCSS[i]}");
    }
  }

  /// Gets string between the first occurences of two strings.
  ///
  /// Example: stringBetween("::Ymy string::F", "::Y", "::F")
  /// returns "my string".
  static String? stringBetween(String input, String start, String end) {
    final startIndex = input.indexOf(start);
    final endIndex = input.indexOf(end);

    if (startIndex != -1 && endIndex != -1 && startIndex < endIndex) {
      final extractedText =
          input.substring(startIndex + start.length, endIndex).trim();
      return extractedText;
    }

    return null;
  }

  /// Handles a crash, pretty basic for now. TODO: Use exit code
  /// b == true: PRCSS_DESKTOP
  /// b == false: PRCSS_LOGIN
  static void handleCrash(bool b, int i) {
    String target = b ? PRCSS_DESKTOP : PRCSS_LOGIN;
    print("Crash detected! @ $target <> Code: $i");
    runProcess(3, [target]);
  }

  /// Log in using a username and a password.
  static Future<bool> login(String username, String password) async {
    // Start the shell process
    final process = await Process.start('/bin/sh', []);

    // Set up process input/output streams
    final stdin = process.stdin;
    final stdout = process.stdout.transform(utf8.decoder);
    //final stderr = process.stderr.transform(utf8.decoder);

    // Wait for the login prompt
    await stdout.firstWhere((line) => line.contains('login:'));

    // Send the username
    stdin.writeln(username);

    // Wait for the password prompt
    await stdout.firstWhere((line) => line.contains('Password:'));

    // Send the password
    stdin.writeln(password);

    // Wait for the login result
    final loginResult = await stdout.firstWhere((line) =>
        line.contains('Login incorrect') || line.contains('Last login:'));

    if (loginResult.contains('Login incorrect')) {
      print('Login failed.');
      process.kill();
      _isLoggedIn = false;
      return false;
    } else {
      print('Login successful.');
      process.kill();

      // Perform additional actions after successful login
      {
        _Core.runProcess(2);
      }

      _isLoggedIn = true;
      return true;
    }
  }

  /// Log out from current user
  static Future<void> logout() async {
    // Start the shell process
    final process = await Process.start('/bin/sh', []);

    // Set up process input/output streams
    final stdin = process.stdin;
    final stdout = process.stdout.transform(utf8.decoder);
    //final stderr = process.stderr.transform(utf8.decoder);

    // Wait for the shell prompt
    await stdout.firstWhere((line) => line.contains('\$'));

    // Send the logout command
    stdin.writeln('logout');

    // Wait for the logout process to complete
    await process.exitCode;

    // Close the process
    process.kill();

    _Core.runProcess(1);
    _isLoggedIn = false;
  }

  /// Check if logged in
  static bool isLoggedIn() => _isLoggedIn;
}
