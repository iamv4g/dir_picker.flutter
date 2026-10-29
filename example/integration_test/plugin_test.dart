import 'package:flutter_test/flutter_test.dart';

import 'list_entries.dart' as list_entries;
import 'persist.dart' as persist;

/// The only entry point: `flutter test integration_test` on desktop can't
/// start the app a second time, so every file after the first fails to load.
void main() {
  group('listEntries', list_entries.main);
  group('persist', persist.main);
}
