#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint dir_picker.podspec` to validate before publishing.
#
require 'yaml'
pubspec = YAML.load_file(File.join(__dir__, '..', 'pubspec.yaml'))

Pod::Spec.new do |s|
  s.name             = pubspec['name']
  s.version          = pubspec['version']
  s.summary          = 'Directory Picker via FFI for iOS and macOS'
  s.description      = <<-DESC
A Flutter plugin for picking directories on iOS and macOS using FFI and DartApiDl NativePort.
                       DESC
  s.homepage         = 'https://github.com/iamv4g/dir_picker.flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'iamv4g' => 'iamv4g.dev@gmail.com' }

  s.source           = { :path => '.' }
  s.source_files = 'dir_picker/Sources/**/*.{h,c,swift}'
  s.public_header_files = [
    'dir_picker/Sources/DartApiDl/include/dart_api_dl.h',
    'dir_picker/Sources/dir_picker/include/dir_picker_ffi.h'
  ]

  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'

  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'

  s.resource_bundles = {
    'dir_picker_privacy' => ['dir_picker/Sources/dir_picker/PrivacyInfo.xcprivacy']
  }
  s.preserve_paths = 'dir_picker/Sources/DartApiDl/include/module.modulemap'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'SWIFT_INCLUDE_PATHS' => '$(PODS_TARGET_SRCROOT)/dir_picker/Sources/DartApiDl/include',
    'OTHER_CFLAGS' => '-I$(PODS_TARGET_SRCROOT)/dir_picker/Sources/DartApiDl/include'
  }
  s.swift_version = '5.9'
end
