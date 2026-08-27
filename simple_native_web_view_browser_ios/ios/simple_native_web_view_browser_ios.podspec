Pod::Spec.new do |s|
  s.name             = 'simple_native_web_view_browser_ios'
  s.version          = '0.3.1'
  s.summary          = 'Простой нативный браузер для iOS'
  s.description      = <<-DESC
iOS implementation of simple_native_web_view_browser
                       DESC
  s.homepage         = 'https://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'simple_native_web_view_browser'
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  s.frameworks = 'WebKit'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
