import 'dart:io';

import 'package:dcli/dcli.dart' show PackedResource;
import 'package:dcli/posix.dart' show chmod;
import 'package:path/path.dart' as p;

void validateResourcePath(String path) {
  final parts = path.split('/');
  if (path.isEmpty ||
      p.posix.isAbsolute(path) ||
      p.windows.isAbsolute(path) ||
      RegExp(r'[\x00-\x1f\x7f-\x9f\\:<>"|?*]').hasMatch(path) ||
      parts.any(
        (part) =>
            part.isEmpty ||
            part == '.' ||
            part == '..' ||
            part.endsWith('.') ||
            part.endsWith(' ') ||
            RegExp(
              r'^(con|conin\$|conout\$|prn|aux|nul|com[1-9¹²³]|lpt[1-9¹²³]) *(?:\.|$)',
              caseSensitive: false,
            ).hasMatch(part),
      )) {
    throw ArgumentError.value(path, 'path', 'Expected a safe relative path');
  }
}

void validateExecutableName(String name) {
  validateResourcePath(name);
  if (name.contains('/')) {
    throw ArgumentError.value(name, 'name', 'Expected one filename');
  }
}

/// Extracts one embedded resource using the trusted-ancestor contract below.
void unpackResource(String installPath, PackedResource resource) {
  validateResourcePath(resource.originalPath);
  final destination = p.join(installPath, resource.originalPath);
  checkDirectory(p.dirname(destination), create: true);
  stageFile(destination, resource.unpack, preserveExistingPermissions: true);
}

/// Every ancestor must be protected against concurrent untrusted changes.
/// These pathname checks are not a substitute for openat/no-follow operations.
void checkDirectory(String path, {bool create = false}) {
  final absolute = p.normalize(p.absolute(path));
  final parent = p.dirname(absolute);
  if (parent != absolute) {
    checkDirectory(parent, create: create);
  }
  final type = FileSystemEntity.typeSync(absolute, followLinks: false);
  if (type == FileSystemEntityType.notFound && create) {
    Directory(absolute).createSync();
  } else if (type != FileSystemEntityType.directory) {
    throw FileSystemException(
      'Expected a directory without symlinks',
      absolute,
    );
  }
}

void checkFileDestination(String path) {
  checkDirectory(p.dirname(path));
  final type = FileSystemEntity.typeSync(path, followLinks: false);
  if (type != FileSystemEntityType.notFound &&
      type != FileSystemEntityType.file) {
    throw FileSystemException('Expected a regular file without symlinks', path);
  }
}

/// Stages on the destination filesystem and promotes with one rename, without
/// copy fallback or delete-before-rename. Callers must protect all ancestors
/// throughout. Windows callers must provide a private inherited ACL and exclude
/// reparse points; dart:io cannot establish these guarantees portably.
/// The write callback must be trusted.
/// It must not replace the staging directory.
void stageFile(
  String destination,
  void Function(String path) write, {
  String? permission,
  bool preserveExistingPermissions = false,
}) {
  final target = p.normalize(p.absolute(destination));
  checkFileDestination(target);
  if (permission != null && preserveExistingPermissions) {
    throw ArgumentError('Specify either permission or preservation');
  }
  // An existing resource can be private or executable. Renaming a fresh inode
  // over it would otherwise replace its mode with the process umask default.
  final existingMode =
      !Platform.isWindows &&
          preserveExistingPermissions &&
          FileSystemEntity.typeSync(target, followLinks: false) ==
              FileSystemEntityType.file
      ? (File(target).statSync().mode & 0x1ff).toRadixString(8).padLeft(3, '0')
      : null;
  final staging = Directory(p.dirname(target)).createTempSync('.self-');
  try {
    if (!Platform.isWindows) {
      chmod(staging.path, permission: '700');
    }
    final staged = p.join(staging.path, 'payload');
    write(staged);
    if (FileSystemEntity.typeSync(staged, followLinks: false) !=
        FileSystemEntityType.file) {
      throw FileSystemException(
        'Staging did not produce a regular file',
        staged,
      );
    }
    final effectivePermission = permission ?? existingMode;
    if (!Platform.isWindows && effectivePermission != null) {
      chmod(staged, permission: effectivePermission);
    }
    checkFileDestination(target);
    File(staged).renameSync(target);
  } finally {
    // Never recurse into an unexpected replacement directory or link.
    if (FileSystemEntity.typeSync(staging.path, followLinks: false) ==
        FileSystemEntityType.directory) {
      final payload = p.join(staging.path, 'payload');
      final type = FileSystemEntity.typeSync(payload, followLinks: false);
      if (type == FileSystemEntityType.file) {
        File(payload).deleteSync();
      }
      if (type == FileSystemEntityType.link) {
        Link(payload).deleteSync();
      }
      staging.deleteSync();
    }
  }
}
