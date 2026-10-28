import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// The X11 window ID of the app's top-level GTK window, or `null` when it
/// can't be found: on Wayland, without GTK, or without a window.
///
/// Calls GTK, so it must run on the GTK main thread. Flutter on Linux runs
/// the root isolate there.
int? appWindowXid() {
  try {
    final gtk = DynamicLibrary.open('libgtk-3.so.0');
    final gdk = DynamicLibrary.open('libgdk-3.so.0');
    final gobject = DynamicLibrary.open('libgobject-2.0.so.0');
    final glib = DynamicLibrary.open('libglib-2.0.so.0');

    final listToplevels = gtk
        .lookupFunction<Pointer<_GList> Function(), Pointer<_GList> Function()>(
          'gtk_window_list_toplevels',
        );
    final isActive = gtk
        .lookupFunction<
          Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('gtk_window_is_active');
    final isVisible = gtk
        .lookupFunction<
          Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('gtk_widget_get_visible');
    final widgetWindow = gtk
        .lookupFunction<
          Pointer<Void> Function(Pointer<Void>),
          Pointer<Void> Function(Pointer<Void>)
        >('gtk_widget_get_window');
    final windowDisplay = gdk
        .lookupFunction<
          Pointer<Void> Function(Pointer<Void>),
          Pointer<Void> Function(Pointer<Void>)
        >('gdk_window_get_display');
    final x11Xid = gdk
        .lookupFunction<
          UnsignedLong Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('gdk_x11_window_get_xid');
    final typeName = gobject
        .lookupFunction<
          Pointer<Utf8> Function(Size),
          Pointer<Utf8> Function(int)
        >('g_type_name');
    final listFree = glib
        .lookupFunction<
          Void Function(Pointer<_GList>),
          void Function(Pointer<_GList>)
        >('g_list_free');

    // Prefer the active window, then the first visible one.
    final list = listToplevels();
    Pointer<Void>? window;
    try {
      for (var node = list; node != nullptr; node = node.ref.next) {
        final widget = node.ref.data;
        if (isVisible(widget) == 0) continue;
        if (isActive(widget) != 0) {
          window = widget;
          break;
        }
        window ??= widget;
      }
    } finally {
      listFree(list);
    }

    final gdkWindow = window == null ? nullptr : widgetWindow(window);
    if (gdkWindow == nullptr) return null;

    // G_OBJECT_TYPE_NAME(display): GTypeInstance starts with its GTypeClass
    // pointer, and GTypeClass starts with the GType.
    final display = windowDisplay(gdkWindow);
    final type = display.cast<Pointer<Size>>().value.value;
    if (typeName(type).toDartString() != 'GdkX11Display') return null;

    final xid = x11Xid(gdkWindow);
    return xid == 0 ? null : xid;
  } on Object {
    // A missing library or symbol: no parent window.
    return null;
  }
}

final class _GList extends Struct {
  external Pointer<Void> data;
  external Pointer<_GList> next;
  external Pointer<_GList> prev;
}
