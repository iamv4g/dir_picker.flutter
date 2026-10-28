# Consumer rules, merged into every app that depends on dir_picker. Keep them
# scoped to this package.
#
# The JNI bindings (lib/src/platforms/android/native_bindings.g.dart) look up
# these classes and their members by name from Dart, which R8 can't see.
-keep class com.iamv4g.dir_picker.** { *; }
