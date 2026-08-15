#include <stdint.h>

// CocoaPods requires at least one source file for the plugin target.
// The real implementation is force-loaded from libpixelcraft_gpu_native.a.
extern uint32_t pixelcraft_gpu_wgpu_abi_version(void);

uint32_t pixelcraft_gpu_link_anchor(void) {
  return pixelcraft_gpu_wgpu_abi_version();
}
