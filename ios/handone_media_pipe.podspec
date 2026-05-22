#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint handone_media_pipe.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'handone_media_pipe'
  s.version          = '0.0.1'
  s.summary          = 'HandOne AR'
  s.description      = <<-DESC
HandOne AR
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'handone_media_pipe/Sources/handone_media_pipe/**/*.swift'
  s.resource_bundles = {
    'handone_media_pipe_privacy' => ['handone_media_pipe/Sources/handone_media_pipe/Resources/PrivacyInfo.xcprivacy']
  }
  s.resources = 'handone_media_pipe/Sources/handone_media_pipe/Resources/*.task'
  s.dependency 'Flutter'
  s.dependency 'MediaPipeTasksVision', '~> 0.10.0'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'BUILD_LIBRARY_FOR_DISTRIBUTION' => 'YES'
  }
  s.swift_version = '5.0'
  s.static_framework = true
end
