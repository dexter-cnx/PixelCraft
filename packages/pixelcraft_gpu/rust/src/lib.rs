use std::panic::{catch_unwind, AssertUnwindSafe};

const BACKEND_VULKAN: u32 = 1 << 0;
const BACKEND_METAL: u32 = 1 << 1;
const BACKEND_DX12: u32 = 1 << 2;
const BACKEND_GL: u32 = 1 << 3;

fn backend_bit(backend: wgpu::Backend) -> u32 {
    match backend {
        wgpu::Backend::Vulkan => BACKEND_VULKAN,
        wgpu::Backend::Metal => BACKEND_METAL,
        wgpu::Backend::Dx12 => BACKEND_DX12,
        wgpu::Backend::Gl => BACKEND_GL,
        _ => 0,
    }
}

fn enumerate() -> Vec<wgpu::Adapter> {
    let instance = wgpu::Instance::new(&wgpu::InstanceDescriptor::default());
    pollster::block_on(instance.enumerate_adapters(wgpu::Backends::all()))
}

/// Returns a bit mask of native GPU backends visible to wgpu.
///
/// bit 0: Vulkan, bit 1: Metal, bit 2: Direct3D 12, bit 3: OpenGL/GLES.
/// Returns 0 if probing fails or no adapter is available.
#[no_mangle]
pub extern "C" fn pixelcraft_gpu_wgpu_backend_mask() -> u32 {
    catch_unwind(AssertUnwindSafe(|| {
        enumerate()
            .into_iter()
            .fold(0, |mask, adapter| mask | backend_bit(adapter.get_info().backend))
    }))
    .unwrap_or(0)
}

/// Returns the number of adapters visible to wgpu.
/// Returns 0 if probing fails.
#[no_mangle]
pub extern "C" fn pixelcraft_gpu_wgpu_adapter_count() -> u32 {
    catch_unwind(AssertUnwindSafe(|| enumerate().len() as u32)).unwrap_or(0)
}

/// Stable ABI version for the Flutter/native boundary.
#[no_mangle]
pub extern "C" fn pixelcraft_gpu_wgpu_abi_version() -> u32 {
    1
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn backend_bits_are_stable() {
        assert_eq!(backend_bit(wgpu::Backend::Vulkan), 1);
        assert_eq!(backend_bit(wgpu::Backend::Metal), 2);
        assert_eq!(backend_bit(wgpu::Backend::Dx12), 4);
        assert_eq!(backend_bit(wgpu::Backend::Gl), 8);
    }

    #[test]
    fn abi_version_starts_at_one() {
        assert_eq!(pixelcraft_gpu_wgpu_abi_version(), 1);
    }
}
