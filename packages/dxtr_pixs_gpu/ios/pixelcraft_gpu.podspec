Pod::Spec.new do |s|
  s.name             = 'pixelcraft_gpu'
  s.version          = '0.1.0'
  s.summary          = 'PixelCraft preview-only native GPU runtime.'
  s.description      = <<-DESC
Preview-only Metal and AVFoundation runtime for PixelCraft. Rust remains authoritative for committed edit semantics and full-resolution export.
                       DESC
  s.homepage         = 'https://github.com/dexter-cnx/PixelCraft'
  s.license          = { :type => 'MIT' }
  s.author           = { 'PixelCraft' => 'pixelcraft@local' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'
  s.static_framework = true
  s.frameworks       = 'AVFoundation', 'CoreMedia', 'CoreVideo', 'Metal', 'MetalKit', 'QuartzCore', 'UIKit'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
