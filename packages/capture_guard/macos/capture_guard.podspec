Pod::Spec.new do |s|
  s.name             = 'capture_guard'
  s.version          = '0.0.1'
  s.summary          = 'Blocks and detects screen capture for TIHE Live.'
  s.description      = 'Native half of capture_guard: see docs/adr/0011-live-capture-guard-censor-and-attribute.md.'
  s.homepage         = 'https://github.com/bambadamin-lang/tihe-live'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'TIHE Live' => 'dev@tihe.ir' }

  s.source           = { :path => '.' }
  s.source_files = 'capture_guard/Sources/capture_guard/**/*'

  # If your plugin requires a privacy manifest, for example if it collects user
  # data, update the PrivacyInfo.xcprivacy file to describe your plugin's
  # privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'capture_guard_privacy' => ['capture_guard/Sources/capture_guard/PrivacyInfo.xcprivacy']}

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
