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

/// Core process name
const String PRCSS_CORE_THIS = "jappeos_core";

/// Login app process name
const String PRCSS_LOGIN = "jappeos_login";

/// Desktop app process name
const String PRCSS_DESKTOP = "jappeos_desktop";

/// Crash handler app process name
const String PRCSS_CRASH_HANDLE = "jappeos_crh";

/// A list of processes
const List<String> PRCSS = [PRCSS_CORE_THIS, PRCSS_LOGIN, PRCSS_DESKTOP, PRCSS_CRASH_HANDLE];

// Whether logged in or not
bool _isLoggedIn = false;

// Startup
bool _shouldQuit = false;
Future<void> main(List<String> arguments) async {
  if (await _Core.isAppRunning(0)) {
    print("Already running! Exiting...");
    exit(0);
  } else {
    _Core.runProcess(1);
  }

  String end = r"$end";
  String from = r"$from";

  final receivePipePath = "${Platform.executable}/pipe/core/";

  // Create a named pipe (FIFO) for receiving messages
  await Process.run('mkfifo', [receivePipePath]);

  // Open the receive pipe for reading
  final receivePipe = File(receivePipePath).openRead();
  while (!_shouldQuit) {
    if (!_isLoggedIn && !await _Core.isAppRunning(1)) {
      _Core.handleCrash(false);
    }
    if (_isLoggedIn && !await _Core.isAppRunning(2)) {
      _Core.handleCrash(true);
    }

    final data = await receivePipe.first;
    final message = utf8.decode(data).trim();
    print('Received message: $message');

    // Execute your function or perform desired actions based on the received message
    if (message.startsWith("login ")) {
      _Core.login(_Core.stringBetween(message, "u:", "p:") ?? "", _Core.stringBetween(message + end, "p:", end) ?? "");
    }
    if (message.startsWith("logout")) {
      _Core.logout();
    }
    if (message.startsWith("logged-in ")) {
      final sendPipePath = _Core.stringBetween(message + end, from, end);

      // Open the send pipe for writing
      final sendPipe = File(sendPipePath!).openWrite(mode: FileMode.append);

      final send = 'logged-in v:${_Core.isLoggedIn()}';

      // Write the message to the send pipe
      sendPipe.writeln(send);
      print('Sent message: $send');

      // Close the send pipe
      sendPipe.close();
    }
    if (message.startsWith("shutdown")) {
      _shouldQuit = true;
    }
  }

  receivePipe.drain();
  await Process.run('rm', [receivePipePath]);

  for (int i = 0; i < PRCSS.length; i++) {
    _Core.killProcess(i);
  }
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
    for (int j = 0; j < PRCSS.length; j++) {
      if (j != i) killProcess(i);
    }

    final result = await Process.run(PRCSS[i], args ?? []);
    print("Process ran: ${PRCSS[i]} :: $result");
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
      final extractedText = input.substring(startIndex + start.length, endIndex).trim();
      return extractedText;
    }

    return null;
  }

  /// Handles a crash, pretty basic for now. TODO: Use exit code
  static void handleCrash(bool b) {
    String target = b ? PRCSS_DESKTOP : PRCSS_LOGIN;
    print("Crash detected! @ $target");
    runProcess(3, [target]);
  }

  /// Log in using a username and a password.
  static Future<bool> login(String username, String password) async {
    final username = 'your_username'; // Replace with your login username
    final password = 'your_password'; // Replace with your login password

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
    final loginResult = await stdout.firstWhere((line) => line.contains('Login incorrect') || line.contains('Last login:'));

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
