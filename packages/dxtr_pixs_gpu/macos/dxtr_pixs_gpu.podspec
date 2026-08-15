Pod::Spec.new do |s|
  s.name             = 'dxtr_pixs_gpu'
  s.version          = '0.1.0'
  s.summary          = 'Cross-platform wgpu preview core for PixelCraft.'
  s.description      = <<-DESC
Preview-only GPU control plane with a shared Rust/wgpu desktop core.
                       DESC
  s.homepage         = 'https://github.com/dexter-cnx/PixelCraft'
  s.license          = { :type => 'MIT' }
  s.author           = { 'PixelCraft' => 'dev@pixelcraft.local' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.15'
  s.swift_version = '5.0'

  s.script_phase = {
    :name => 'Build Rust wgpu library',
    :script => 'sh "$PODS_TARGET_SRCROOT/../../dxtr_pixs_engine/cargokit/build_pod.sh" ../rust pixelcraft_gpu_native',
    :execution_position => :before_compile,
    :input_files => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
    :output_files => ["${BUILT_PRODUCTS_DIR}/libpixelcraft_gpu_native.a"],
  }

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'OTHER_LDFLAGS' => '-force_load ${BUILT_PRODUCTS_DIR}/libpixelcraft_gpu_native.a',
  }
end
