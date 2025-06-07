# overview
The Self package provides utility classes to make it easy 
to create Self extracting executables that ship with resources
or need to run on boot.

The Self package utilises the [DCli](https://pub.dev/packages/dcli) `pack` command to create the
self extracting exe.

As well as creating a self extracting executable, Self includes a utility
to add your executable as a cronjob so that the exectuable is launched
each time the system boots.

You can also use the automatic restart service to relaunch your
executable if it should crash (exits with a non-zero exit code)

# install

To use the Self package you need to install the [dcli_sdk](https://pub.dev/packages/dcli_sdk)

```bash
dart pub global activate dcli_sdk
sudo env PATH="$PATH" dcli install
```

You can ignore the warnings about running Flutter as root.


Now add the Self package to your project.

```bash
cd <my project>
dart pub add self
```

# companion packages

We recommend installing the following companion packages.
| package | details |
|--- | --- |
| [args](https://pub.dev/packages/args)   | process command line args |
| [path](https://pub.dev/packages/path) |  work with file paths |
| [dcli_core](https://pub.dev/packages/dcli_core) | filesystem management tools |
| [dcli](https://pub.dev/packages/dcli) |  process launchers and cli helper functions  |


# implementing
The self package needs to be called from you apps 'main' function.

You will normally do this be adding a number of command line arguments to the startup logic.

The easiest way to do this is using the [args](https://pub.dev/pacakges/args) 
package.

We recommend you add the following command line args.
 * install - extract the exectuable and any resources.
 * launch - lauches the executable and restart if it ever crashes.
 * run - runs the app.
 
 Example:

 See example/main.dart for the full source code.

 ```dart
   ..addFlag(
      'launch',
      abbr: 'l',
      negatable: false,
      help: '''
Launches the application as a sub-process and will restart it if it crashes.
''',
    )
    ..addFlag(
      'run',
      abbr: 'r',
      negatable: false,
      help: '''
Run the application.
''',
    )
    ..addFlag(
      'install',
      abbr: 'i',
      negatable: false,
      help: '''
Extracts and installs the application, adding a cronjob so it launches on boot.
''',
    )
    ..addFlag('debug', abbr: 'd', help: 'Enable fine logging')
    ..addFlag('help', help: 'Print the usage message');

  // for the moment we don't want to be running as sudo
  // as it screws up env vars and file permissions.
  Shell.current.releasePrivileges();

  // parse the command line arguments.
  ArgResults? results;
  try {
    results = parser.parse(args);
  } on FormatException catch (e) {
    print(red(e.message));
    print(parser.usage);
    await exitWithFlush(1);
  }

  final run = results!.flag('run');
  final install = results.flag('install');
  final launch = results.flag('launch');
  final debug = results.flag('debug');
  final help = results.flag('help');

  if (help) {
    print('''A description of what your app does''');
    print(parser.usage);
    await exitWithFlush(0);
  }

  // The user must pass exactly one of the flags.
  if (!_exactlyOne(install: install, launch: launch, run: run)) {
    printerr(red('You must pass one of --install, --launch, --run'));
    print(parser.usage);
    await exitWithFlush(1);
  }

  // MyLogger implements SelfLogger so [Self] can
  // log through your existing logging system.
  logger = await MyLogger.create(logFilePath: './logfile.log', debug: debug);
  final self = Self(
    logger: logger,
    installPath: '$HOME/myapp',
    executableName: 'myapp',
    resources: ResourceRegistry.resources,
  );

  if (install) {
    await _install(self);
  }

  if (launch) {
    await _launch(args, self);
  }

  if (run) {
    await _run(args, logger);
  }

  // Use a 0 exit code to tell the launcher not to restart us as we are 
  // shutting down intentionally.
  //
  // technically not required as if we return from main
  // the app exit with a non-zero exit code anyway.
  await exitWithFlush(0);
}

 ```

# resources

Self with the help of the 'dcli pack' allows you to pack self extracting resources (including binary files) into your executable.

[dcli pack documenation](https://dcli.onepub.dev/dcli-api/assets)

To build your application you need to pack any resources before you compile your application.

Create a directory under the root of your project:

```bash
cd <my project>
mkdir resource
```

Place any assets (files) you want to ship with your executable into the
resource directory.

## Advanced packing
If you resources are external to your project ( or need to be located in other directories ) you can create a `pack.yaml` file in the resource directory that lists the files to be packed.


[Advanced resources packing guide](https://dcli.onepub.dev/dcli-api/assets#external-resources)

# building

We recommend creating a build script to pack and compile your executable:

`touch <my project>/tool/build.dart`

```dart
#! /usr/bin/dart 
# update the above path to whereever your dart exe is installed
# run `which dart` to find the path.


void main() {
  // run `dart pub get` to ensure everything is up to date.
  _runPubGet();
  print(green('packing resources'));
  'dcli pack'.run;

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


```

To run you build script:

Linux/MacOs:
```bash
chmod +x tool/build.dart
tool/build.dart
```

Windows:
```bash
dart tool/build.dart
```

The build script will create an executable in you project root directory called `<myapp>`_instaler. 
On Windows it will end in .exe.

# deploying
Once you have created your installer you need to deploy it.

Copy the  installer to the target system and run:

Linux/MacOS
```bash
chmod +x my_app_installer
sudo env PATH="$PATH" ./my_app_installer
```

Window: 
```bash
my_app_installer
```

# sudo
On Linux and MacOs you may need to run the installer as sudo if it needs
to create directories outside of you home directory.

NOTE: you shoud never run a .dart file as sudo as it is likely to break your
dart SDK.

To run a dart app as sudo you MUST first compile the app. Once the app has been 
compiled you can run the app with:

```bash
sudo env PATH="$PATH" ./my_app_installer
```

The DCli SDK provides tools to help you iteract with the file system when
running as sudo.

[Elevated Privileges](https://dcli.onepub.dev/elevated-privileges)

# self
