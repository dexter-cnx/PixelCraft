# pixelcraft_gpu

Preview-only GPU control plane for PixelCraft.

This package may represent and transport interactive preview state, but it never owns committed edit semantics. Rust remains authoritative for recipes, history, checkpoints, recovery, and full-resolution export. Camera frame buffers stay native and never cross Dart MethodChannel or Flutter Rust Bridge.
