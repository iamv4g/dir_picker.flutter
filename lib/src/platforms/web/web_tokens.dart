import 'dart:async';
import 'dart:js_interop';
import 'dart:math';

import 'package:web/web.dart' as web;

// Tokens for the web implementation. A FileSystemDirectoryHandle can't be
// turned into a string, but it can be stored in IndexedDB, so the plugin
// keeps the handles in its own object store and the token is the record key.

const _databaseName = 'dir_picker';
const _storeName = 'locations';

/// Stores [handle] and returns its key. A handle for the same directory as
/// one already stored gets that record's key, as on Android, where the token
/// is the folder's URI.
Future<String> storeHandle(web.FileSystemDirectoryHandle handle) async {
  final (keys, handles) = await _transact('readonly', (store) async {
    final keys = store.getAllKeys();
    final handles = store.getAll();
    return (await _result(keys), await _result(handles));
  });
  final keyList = (keys as JSArray<JSString>).toDart;
  final handleList = (handles as JSArray<web.FileSystemHandle>).toDart;
  for (var i = 0; i < keyList.length; i++) {
    if (await handleList[i].isSameEntry(handle).toDart.then((s) => s.toDart)) {
      return keyList[i].toDart;
    }
  }

  final key = _newKey();
  await _transact('readwrite', (store) => _result(store.put(handle, key.toJS)));
  return key;
}

/// The handle stored under [key], or `null` when there is none.
Future<web.FileSystemDirectoryHandle?> loadHandle(String key) async {
  final value = await _transact(
    'readonly',
    (store) => _result(store.get(key.toJS)),
  );
  return value != null && value.isA<web.FileSystemDirectoryHandle>()
      ? value as web.FileSystemDirectoryHandle
      : null;
}

/// Deletes the record stored under [key], if any.
Future<void> deleteHandle(String key) =>
    _transact('readwrite', (store) => _result(store.delete(key.toJS)));

/// The keys of every stored handle.
Future<List<String>> storedKeys() async {
  final keys = await _transact(
    'readonly',
    (store) => _result(store.getAllKeys()),
  );
  return [for (final key in (keys as JSArray<JSString>).toDart) key.toDart];
}

/// 128 random bits as hex, so a token can't be guessed or collide.
String _newKey() {
  final random = Random.secure();
  return [
    for (var i = 0; i < 16; i++)
      random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}

/// Runs [body] in a transaction on the store and returns its result once the
/// transaction has committed.
Future<T> _transact<T>(
  String mode,
  Future<T> Function(web.IDBObjectStore store) body,
) async {
  final database = await _open();
  try {
    final transaction = database.transaction(_storeName.toJS, mode);
    final done = Completer<void>();
    // A failed request fires both error and abort on the transaction.
    void fail(web.Event _) {
      if (!done.isCompleted) done.completeError(_error(transaction.error));
    }

    transaction
      ..oncomplete = ((web.Event _) => done.complete()).toJS
      ..onerror = fail.toJS
      ..onabort = fail.toJS;
    final T result;
    try {
      result = await body(transaction.objectStore(_storeName));
    } catch (_) {
      // The failed request aborts the transaction, which fails [done] too.
      done.future.ignore();
      rethrow;
    }
    await done.future;
    return result;
  } finally {
    database.close();
  }
}

Future<web.IDBDatabase> _open() async {
  final request = web.window.indexedDB.open(_databaseName, 1);
  request.onupgradeneeded = ((web.Event _) {
    (request.result as web.IDBDatabase).createObjectStore(_storeName);
  }).toJS;
  return await _result(request) as web.IDBDatabase;
}

/// The result of [request], or its error.
Future<JSAny?> _result(web.IDBRequest request) {
  final completer = Completer<JSAny?>();
  request
    ..onsuccess = ((web.Event _) => completer.complete(request.result)).toJS
    ..onerror = ((web.Event _) => completer.completeError(
      _error(request.error),
    )).toJS;
  return completer.future;
}

Object _error(web.DOMException? error) =>
    error ?? Exception('IndexedDB request failed without an error');
