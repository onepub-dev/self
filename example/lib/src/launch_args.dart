import 'package:args/args.dart';

/// Construct child mode from parsed options, never forward launcher aliases.
List<String> childArguments(ArgResults results) => [
  '--run',
  if (results.flag('debug')) '--debug',
];
