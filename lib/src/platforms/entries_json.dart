import 'dart:convert';

import '../location/file_system_entry.dart';

/// Decodes the JSON array that the native `listEntries` implementations
/// (Darwin and Android) report.
List<FileSystemEntry> decodeEntriesJson(String json) {
  final decoded = jsonDecode(json) as List<Object?>;
  return decoded
      .map((entry) => FileSystemEntry.fromJson(entry! as Map<Object?, Object?>))
      .toList(growable: false);
}
