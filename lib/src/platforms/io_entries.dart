import 'dart:io';

import 'package:path/path.dart' as p;

import '../location/file_system_entry.dart';

/// Lists [root] with `dart:io`, for the Linux and Windows implementations.
///
/// A symbolic link is reported as what it points to, but never followed, so a
/// link to a directory is a directory entry whose contents aren't listed. A
/// subdirectory that can't be read is skipped, as `FileManager` does on iOS
/// and macOS. Only a failure to list [root] itself throws.
Future<List<FileSystemEntry>> listIoEntries(
  Directory root, {
  required bool recursive,
}) async {
  final entries = <FileSystemEntry>[];

  Future<void> list(Directory directory, String parentPath) async {
    await for (final entity in directory.list(followLinks: false)) {
      final name = p.basename(entity.path);
      final relativePath = parentPath.isEmpty ? name : '$parentPath/$name';
      // stat() follows links; a broken link comes back as notFound.
      final stat = await entity.stat();
      entries.add(
        FileSystemEntry(
          name: name,
          relativePath: relativePath,
          isDirectory: stat.type == FileSystemEntityType.directory,
          uri: entity.uri,
          size: stat.type == FileSystemEntityType.file ? stat.size : null,
          lastModified: stat.type == FileSystemEntityType.notFound
              ? null
              : stat.modified,
        ),
      );

      if (recursive && entity is Directory) {
        try {
          await list(entity, relativePath);
        } on FileSystemException {
          // Unreadable subdirectory: keep the entry, skip its contents.
        }
      }
    }
  }

  await list(root, '');
  return entries;
}
