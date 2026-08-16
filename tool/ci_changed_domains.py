#!/usr/bin/env python3
"""Classify changed repository paths into PixelCraft CI domains.

This script is intentionally dependency-free so the change-detection job can run
before Flutter/Rust setup. It can emit GitHub Actions outputs or be exercised
locally with --self-test.
"""

from __future__ import annotations

import argparse
import fnmatch
from pathlib import Path
from typing import Iterable

DOMAINS = (
    "docs",
    "flutter_app",
    "flutter_packages",
    "native_gpu",
    "android",
    "ios",
    "macos",
    "windows_linux",
    "package_api",
    "reliability",
    "ci",
)


def _match(path: str, *patterns: str) -> bool:
    return any(fnmatch.fnmatch(path, pattern) for pattern in patterns)


def _is_docs(path: str) -> bool:
    name = Path(path).name
    return path.startswith("docs/") or name.startswith("README") or path.endswith(".md")


def classify(paths: Iterable[str]) -> dict[str, bool]:
    files = sorted({p.strip().replace("\\", "/") for p in paths if p.strip()})
    result = {domain: False for domain in DOMAINS}
    shared_native_gpu = False

    for path in files:
        if _is_docs(path):
            result["docs"] = True

        if _match(
            path,
            "lib/**",
            "test/**",
            "integration_test/**",
            "test_driver/**",
            "assets/**",
            "pubspec.yaml",
            "pubspec.lock",
            "analysis_options.yaml",
        ):
            result["flutter_app"] = True

        if path.startswith("packages/"):
            result["flutter_packages"] = True

        if _match(path, "android/**", "packages/*/android/**"):
            result["android"] = True
        if _match(path, "ios/**", "packages/*/ios/**"):
            result["ios"] = True
        if _match(path, "macos/**", "packages/*/macos/**"):
            result["macos"] = True
        if _match(
            path,
            "windows/**",
            "linux/**",
            "packages/*/windows/**",
            "packages/*/linux/**",
        ):
            result["windows_linux"] = True

        gpu_path = _match(
            path,
            "packages/dxtr_pixs_gpu/**",
            "rust/**",
            "Cargo.toml",
            "Cargo.lock",
            "tool/generate_gpu_*",
            "integration_test/gpu_preview_harness_test.dart",
            "integration_test/g3_editor_gpu_verification_test.dart",
            "integration_test/native_engine_smoke_test.dart",
            "integration_test/performance_profile_test.dart",
        )
        gpu_name = any(
            token in path.lower()
            for token in ("gpu", "metal", "opengl", "shader", "texture", "renderer")
        ) and _match(path, "android/**", "ios/**", "macos/**", "windows/**", "linux/**")
        if gpu_path or gpu_name:
            result["native_gpu"] = True

        if _match(
            path,
            "rust/**",
            "Cargo.toml",
            "Cargo.lock",
            "packages/dxtr_pixs_gpu/lib/**",
            "packages/dxtr_pixs_gpu/rust/**",
            "packages/dxtr_pixs_gpu/pubspec.yaml",
            "tool/generate_gpu_*",
        ):
            shared_native_gpu = True

        if _match(
            path,
            "packages/*/lib/**",
            "packages/*/pubspec.yaml",
            "packages/*/pubspec.lock",
            "pubspec.yaml",
            "flutter_rust_bridge.yaml",
            "lib/src/rust/**",
            "rust/src/frb_generated.rs",
            "ios/Runner/frb_generated.h",
        ):
            result["package_api"] = True

        if _match(
            path,
            "tool/g6_*.sh",
            "integration_test/g6_*.dart",
            "test/state/g6_*.dart",
            "tool/verify_g3_device.sh",
        ):
            result["reliability"] = True

        if _match(
            path,
            ".github/**",
            "Makefile",
            "tool/ci_*",
            "tool/check_package_boundaries.sh",
        ):
            result["ci"] = True

    result["shared_native_gpu"] = shared_native_gpu
    result["docs_only"] = bool(files) and all(_is_docs(path) for path in files)
    result["has_changes"] = bool(files)
    return result


def _write_outputs(result: dict[str, bool], output_path: str | None) -> None:
    lines = [f"{key}={'true' if value else 'false'}" for key, value in result.items()]
    text = "\n".join(lines) + "\n"
    print(text, end="")
    if output_path:
        with open(output_path, "a", encoding="utf-8") as handle:
            handle.write(text)


def _self_test() -> None:
    cases = [
        (["docs/PROJECT_HANDOFF.md"], {"docs": True, "docs_only": True, "native_gpu": False}),
        (["lib/ui/foo.dart"], {"flutter_app": True, "docs_only": False, "native_gpu": False}),
        (["android/app/build.gradle.kts"], {"android": True, "shared_native_gpu": False}),
        (["packages/dxtr_pixs_gpu/android/src/main/kotlin/Gpu.kt"], {"android": True, "native_gpu": True, "shared_native_gpu": False}),
        (["packages/dxtr_pixs_gpu/rust/src/lib.rs"], {"native_gpu": True, "shared_native_gpu": True, "flutter_packages": True}),
        (["packages/dxtr_pixs_film/lib/src/profile.dart"], {"flutter_packages": True, "package_api": True}),
        (["ios/Runner/GpuPreviewChannel.swift"], {"ios": True, "native_gpu": True, "shared_native_gpu": False}),
        (["tool/g6_run_device_session.sh"], {"reliability": True}),
        ([".github/workflows/ci.yml"], {"ci": True}),
    ]
    for paths, expected in cases:
        actual = classify(paths)
        for key, value in expected.items():
            assert actual[key] is value, (paths, key, actual[key], value)
    print("[PixelCraft CI] change-domain self-test PASS")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="*")
    parser.add_argument("--file-list", help="newline-delimited changed path list")
    parser.add_argument("--github-output", help="append key=value pairs to this file")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        _self_test()
        return

    paths = list(args.paths)
    if args.file_list:
        paths.extend(Path(args.file_list).read_text(encoding="utf-8").splitlines())
    _write_outputs(classify(paths), args.github_output)


if __name__ == "__main__":
    main()
