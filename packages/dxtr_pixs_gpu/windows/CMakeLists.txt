cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "pixelcraft_gpu")
project(${PROJECT_NAME} LANGUAGES CXX)

# Reuse the monorepo CargoKit build driver while pixelcraft_gpu owns its Rust crate.
# This keeps the GPU runtime isolated from pixelcraft_engine semantics.
include("../../pixelcraft_engine/cargokit/cmake/cargokit.cmake")
apply_cargokit(${PROJECT_NAME} ../rust pixelcraft_gpu_native "pixelcraft_gpu_wgpu_abi_version")

set(pixelcraft_gpu_bundled_libraries
  "${${PROJECT_NAME}_cargokit_lib}"
  PARENT_SCOPE
)
