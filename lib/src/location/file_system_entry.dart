class FileSystemEntry {
  const FileSystemEntry({
    required this.name,
    required this.relativePath,
    required this.isDirectory,
    this.uri,
    this.size,
    this.lastModified,
  });

  factory FileSystemEntry.fromJson(Map<Object?, Object?> json) {
    final uriValue = json['uri'] as String?;
    final sizeValue = json['size'];
    final lastModifiedValue = json['lastModified'];

    return FileSystemEntry(
      name: json['name'] as String,
      relativePath: json['relativePath'] as String,
      isDirectory: json['isDirectory'] as bool,
      uri: uriValue == null ? null : Uri.parse(uriValue),
      size: sizeValue == null ? null : (sizeValue as num).toInt(),
      lastModified: lastModifiedValue == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              (lastModifiedValue as num).toInt(),
            ),
    );
  }

  final String name;
  final String relativePath;
  final bool isDirectory;
  final Uri? uri;
  final int? size;
  final DateTime? lastModified;

  Map<String, Object?> toJson() => {
    'name': name,
    'relativePath': relativePath,
    'isDirectory': isDirectory,
    'uri': uri?.toString(),
    'size': size,
    'lastModified': lastModified?.millisecondsSinceEpoch,
  };

  @override
  String toString() =>
      'FileSystemEntry(relativePath: $relativePath, isDirectory: $isDirectory)';
}
