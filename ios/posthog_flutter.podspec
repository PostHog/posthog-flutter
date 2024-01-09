#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint posthog_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'posthog_flutter'
  s.version          = '0.0.1'
  s.summary          = 'The hassle-free way to add posthog to your Flutter app.'
  s.description      = <<-DESC
Postog flutter plugin
                       DESC
  s.homepage         = 'https://posthog.com/'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'PostHog' => 'engineering@posthog.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'PostHog', '~> 3.0.0-beta.2'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
