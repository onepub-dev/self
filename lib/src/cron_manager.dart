// ignore_for_file: avoid_print

import 'package:dcli/dcli.dart';
import 'package:path/path.dart';

import 'self_logger.dart';

class CronManager {
  CronManager(this.logger);

  SelfLogger logger;

  /// Add cron job so we get rebooted each time the system is rebooted.
  /// The cron job is added by creating a file called:
  ///   `/etc/cron.d/<execurable_name>`
  /// The file extension is removed from the name.
  /// You can view the cronjob's details by running:
  /// crontab -l
  void addBoot({
    required String pathToExecutable,
    required List<String> args,
    required String workingDirectory,
    required String runAsUser,
  }) {
    final basename = basenameWithoutExtension(pathToExecutable);
    print('Adding cronjob to start $basename with $args on reboot');

    final expandedArgs = args.join(' ');

    /// Create a cron job that launches the app on boot.
    final pathToCronJob = join(rootPath, 'etc', 'cron.d', basename)
      ..write('''
@reboot   $runAsUser  'cd $workingDirectory && $pathToExecutable $expandedArgs'
''');

    // @reboot  cd /home/bsutton/myapp && ./myapp --launch

    print('''
To view the cron job run:
  cat $pathToCronJob
    ''');
  }
}
