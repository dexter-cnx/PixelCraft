cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "pixelcraft_gpu")
project(${PROJECT_NAME} LANGUAGES CXX)

# Reuse the split engine package's CargoKit build driver while pixelcraft_gpu owns its Rust crate.
include("../../dxtr_pixs_engine/cargokit/cmake/cargokit.cmake")
apply_cargokit(${PROJECT_NAME} ../rust pixelcraft_gpu_native "")

set(pixelcraft_gpu_bundled_libraries
  "${${PROJECT_NAME}_cargokit_lib}"
  PARENT_SCOPE
)
