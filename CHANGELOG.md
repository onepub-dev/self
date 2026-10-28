# 0.8.1
- Quote and validate cron fields and atomically replace cron files.
- Reject unsafe resource paths and symlinks; stage installation files privately
  on the destination filesystem before rename. Existing POSIX resource modes are
  preserved. Trusted ancestors remain required.
- Stop on successful child exit and bound failure restarts (five by default).
- Fix example launch aliases and ensure privilege release on exceptions.

# 0.8.0
- upgraded to dcli 10.0.0

# 0.7.0
- upgraded to dcli 9.0.1.

# 0.6.1
- fixed a bug in the unpack resource logic. If multi-level path
was being unpacked and the parent directory didn't exist the unpack
fails. We now create the directory recursively so all parents are created.

# 0.6.0
- upgraded to dcli 8.2.0

# 0.5.1 
- add 'finer' entry point to the SelfLogger.

# 0.5.0
- upgraded to dcli 8.1.1

# 0.4.0
- Added the ability to provide an alternate cron path in which to place
the cron jobs.

# 0.3.0
- replace sleep with asyncSleep as it was pausing all async operations so logging was not being flushed. upgraded to dcli 7.0.5 to get access sleepAsync
- launch is now async.
- The cron job now changes to a defined working directory.

# 0.2.0
- added missing exports.

# 0.1.0
- First release.
