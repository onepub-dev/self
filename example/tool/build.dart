#! /home/bsutton/apps/flutter/bin/dart
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:dcli/dcli.dart';

void main() {
  // run `dart pub get` to ensure everything is up to date.
  _runPubGet();
  print(green('packing resources'));
  'dcli pack'.run;
  // compiles the exe to bin/myapp_installer or bin/myapp_installer.exe

  print(green('compiling executable'));
  if (Platform.isWindows) {
    'dart compile exe bin/main.dart -o myapp_installer.exe'.run;
  } else {
    'dart compile exe bin/main.dart -o myapp_installer'.run;
  }
}

void _runPubGet() {
  print(green('running dart pub get'));
  DartSdk().runPubGet(DartProject.self.pathToProjectRoot);
}
