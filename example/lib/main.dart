import 'package:dir_picker/dir_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: DirPickerHomePage());
  }
}

class DirPickerHomePage extends StatefulWidget {
  const DirPickerHomePage({super.key});

  @override
  State<DirPickerHomePage> createState() => _DirPickerHomePageState();
}

class _DirPickerHomePageState extends State<DirPickerHomePage> {
  static const _tokenKey = 'dir_picker_example.token';

  String _result = 'Press the button to pick a directory';
  PickedLocation? _pickedLocation;

  /// The saved token of the folder the app remembers. Web can't persist.
  String? _token;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) _restoreSavedFolder();
  }

  /// Reopens the folder picked in an earlier run, without asking again.
  Future<void> _restoreSavedFolder() async {
    final prefs = SharedPreferencesAsync();
    final token = await prefs.getString(_tokenKey);
    if (token == null) return;

    final location = await DirPicker.restore(token);
    if (!mounted) return;
    if (location == null) {
      await prefs.remove(_tokenKey);
      setState(() => _result = 'The remembered folder is no longer available');
      return;
    }
    // On iOS and macOS a moved folder gives a stale bookmark: save a new one.
    final freshToken = await DirPicker.persist(location);
    await prefs.setString(_tokenKey, freshToken);
    setState(() {
      _pickedLocation = location;
      _token = freshToken;
      _result = 'Restored: $location';
    });
  }

  /// Keeps access to [location] for the next run, in place of the folder
  /// remembered before.
  Future<void> _rememberFolder(PickedLocation location) async {
    final prefs = SharedPreferencesAsync();
    final token = await DirPicker.persist(location);
    if (_token case final previous? when previous != token) {
      await DirPicker.release(previous);
    }
    await prefs.setString(_tokenKey, token);
    _token = token;
  }

  Future<void> _forgetFolder() async {
    final token = _token;
    if (token == null) return;
    await DirPicker.release(token);
    await SharedPreferencesAsync().remove(_tokenKey);
    setState(() {
      _token = null;
      _result = 'Forgot the remembered folder';
    });
  }

  Future<PickedLocation?> _pickLocation() {
    return DirPicker.pick(
      // Reopen where the user picked last time, where the platform allows.
      initialDirectory: _pickedLocation,
      options: switch (defaultTargetPlatform) {
        TargetPlatform.android => const PickOptions.android(
          shouldPersist: false,
        ),
        TargetPlatform.macOS => const PickOptions.macos(
          acceptLabel: 'Select Directory',
          message: 'Please choose a directory to continue',
        ),
        TargetPlatform.linux => const PickOptions.linux(
          title: 'Select a directory',
          acceptLabel: 'Choose',
        ),
        TargetPlatform.windows => const PickOptions.windows(
          title: 'Select a directory',
          acceptLabel: 'Choose',
        ),
        _ => null,
      },
    );
  }

  Future<void> _pickDirectory() async {
    try {
      final location = await _pickLocation();
      if (location == null) {
        setState(() {
          _pickedLocation = null;
          _result = 'Cancelled';
        });
        return;
      }

      if (!kIsWeb) await _rememberFolder(location);
      setState(() {
        _pickedLocation = location;
        _result = 'Picked: $location';
      });
    } catch (e) {
      setState(() {
        _pickedLocation = null;
        _result = 'Error: $e';
      });
    }
  }

  Future<void> _openEntriesScreen() async {
    final location = _pickedLocation;
    if (location == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FileEntriesPage(location: location),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dir Picker Example')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_result, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _pickDirectory,
              child: const Text('Pick Directory'),
            ),
            if (_pickedLocation != null) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _openEntriesScreen,
                child: const Text('View Directory Entries'),
              ),
            ],
            if (_token != null) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: _forgetFolder,
                child: const Text('Forget Remembered Folder'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class FileEntriesPage extends StatefulWidget {
  const FileEntriesPage({required this.location, super.key});

  final PickedLocation location;

  @override
  State<FileEntriesPage> createState() => _FileEntriesPageState();
}

class _FileEntriesPageState extends State<FileEntriesPage> {
  String error = '';
  List<FileSystemEntry>? entries;

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final listedEntries = await DirPicker.listEntries(
          widget.location,
          recursive: true,
        );
        if (!mounted) return;
        setState(() => entries = listedEntries);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          entries = [];
          error = 'Error listing entries: $e';
        });
      }
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Directory Entries')),
      body: switch (entries) {
        null => const Center(child: CircularProgressIndicator()),

        final _ when error.isNotEmpty => Center(
          child: Text(error, textAlign: TextAlign.center),
        ),

        [] => Center(
          child: Text(
            'No entries found\n${widget.location}',
            textAlign: TextAlign.center,
          ),
        ),

        final entries => _buildList(entries),
      },
    );
  }

  Widget _buildList(List<FileSystemEntry> entries) {
    final nodes = _buildEntryTree(entries);

    return ListView.builder(
      itemCount: nodes.length,
      itemBuilder: (context, index) {
        return _EntryTile(node: nodes[index]);
      },
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.node});

  final _EntryNode node;

  @override
  Widget build(BuildContext context) {
    final entry = node.entry;

    if (entry.isDirectory) {
      return ExpansionTile(
        leading: const Icon(Icons.folder),
        title: Text(entry.name),
        subtitle: Text(entry.relativePath),
        children: [for (final child in node.children) _EntryTile(node: child)],
      );
    }

    return ListTile(
      leading: const Icon(Icons.insert_drive_file_outlined),
      title: Text(entry.name),
      subtitle: Text(entry.relativePath),
      trailing: entry.size == null ? null : Text(_formatBytes(entry.size!)),
    );
  }
}

class _EntryNode {
  _EntryNode(this.entry);

  final FileSystemEntry entry;
  final List<_EntryNode> children = [];
}

List<_EntryNode> _buildEntryTree(List<FileSystemEntry> entries) {
  final roots = <_EntryNode>[];
  final byPath = <String, _EntryNode>{};
  final sortedEntries = [...entries]
    ..sort((a, b) => a.relativePath.compareTo(b.relativePath));

  for (final entry in sortedEntries) {
    final node = _EntryNode(entry);
    byPath[entry.relativePath] = node;

    final parent = byPath[p.posix.dirname(entry.relativePath)];
    if (parent == null) {
      roots.add(node);
    } else {
      parent.children.add(node);
    }
  }

  return roots;
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  return '${(mb / 1024).toStringAsFixed(1)} GB';
}
