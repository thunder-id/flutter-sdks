Pod::Spec.new do |s|
  s.name             = 'thunderid_flutter'
  s.version          = '0.0.0'
  s.summary          = 'Flutter plugin for ThunderID identity management.'
  s.description      = <<-DESC
    Bridges the Flutter SDK to the native ThunderID iOS Platform SDK via Flutter platform channels.
    All OAuth2/OIDC and token management logic is delegated to the native ThunderID Swift SDK.
  DESC
  s.homepage         = 'https://thunderid.dev'
  s.license          = { :type => 'Apache License 2.0', :file => '../LICENSE' }
  s.author           = { 'ThunderID' => 'dev@thunderid.dev' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency       'Flutter'
  s.dependency       'ThunderID', '~> 0.0'
  s.platform         = :ios, '16.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'SWIFT_STRICT_CONCURRENCY' => 'complete' }
  s.swift_version    = '5.9'
end
