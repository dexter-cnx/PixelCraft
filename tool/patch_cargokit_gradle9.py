#!/usr/bin/env python3
"""Patch FRB 2.12.0 CargoKit output for the current Flutter toolchain.

The generated integration needs two compatibility fixes:
1. Gradle 9 removed Project.exec, so CargoKit must use injected ExecOperations.
2. The generated Android plugin uses compileSdk 33, while current AndroidX
   dependencies require API 34 or newer. PixelCraft standardizes on API 36 and
   keeps minSdk 21.

The operation is idempotent and can recover a Gradle file accidentally replaced
by a shell transcript when the pristine backup is available.
"""
from __future__ import annotations

from pathlib import Path
import re
import sys

GRADLE_PATH = Path("rust_builder/cargokit/gradle/plugin.gradle")
GRADLE_BACKUP = GRADLE_PATH.with_suffix(".gradle.pre-gradle9")
ANDROID_PLUGIN_PATH = Path("rust_builder/android/build.gradle")


def patch_android_plugin() -> None:
    if not ANDROID_PLUGIN_PATH.is_file():
        print(
            f"ERROR: Rust Android plugin not found: {ANDROID_PLUGIN_PATH}",
            file=sys.stderr,
        )
        raise SystemExit(1)

    text = ANDROID_PLUGIN_PATH.read_text(encoding="utf-8")
    original = text

    text, compile_count = re.subn(
        r"(?m)^\s*compileSdkVersion\s+\d+\s*$",
        "    compileSdkVersion 36",
        text,
        count=1,
    )
    text, min_count = re.subn(
        r"(?m)^\s*minSdkVersion\s+\d+\s*$",
        "        minSdkVersion 21",
        text,
        count=1,
    )

    if compile_count != 1 or min_count != 1:
        print(
            "ERROR: Could not locate compileSdkVersion/minSdkVersion in "
            f"{ANDROID_PLUGIN_PATH}.",
            file=sys.stderr,
        )
        raise SystemExit(1)

    if text != original:
        ANDROID_PLUGIN_PATH.write_text(text, encoding="utf-8")
        print(
            "[PixelCraft] Updated Rust Android plugin to "
            "compileSdk 36 / minSdk 21"
        )
    else:
        print(
            "[PixelCraft] Rust Android SDK levels already aligned: "
            "compileSdk 36 / minSdk 21"
        )


def patch_cargokit_gradle() -> None:
    path = GRADLE_PATH
    backup = GRADLE_BACKUP

    if not path.is_file():
        print(f"ERROR: CargoKit Gradle plugin not found: {path}", file=sys.stderr)
        print("Run `make integrate` first.", file=sys.stderr)
        raise SystemExit(1)

    text = path.read_text(encoding="utf-8")

    looks_corrupted = (
        text.startswith("Script started on ")
        or "Command exit status:" in text
        or "Script done on " in text
    )
    if looks_corrupted:
        if not backup.is_file():
            print(
                f"ERROR: {path} is corrupted and no backup exists at {backup}.",
                file=sys.stderr,
            )
            print("Run `make integrate` to regenerate CargoKit.", file=sys.stderr)
            raise SystemExit(1)
        text = backup.read_text(encoding="utf-8")
        path.write_text(text, encoding="utf-8")
        print(f"[PixelCraft] Restored corrupted CargoKit script from {backup}")

    original = text

    text = re.sub(
        r"\b(?:abstract\s+){2,}(class\s+CargoKitBuildTask\s+extends\s+DefaultTask\s*\{)",
        r"abstract \1",
        text,
    )

    if (
        "abstract ExecOperations getExecOperations()" in text
        and "project.exec {" not in text
    ):
        if text != original:
            path.write_text(text, encoding="utf-8")
            print(f"[PixelCraft] Repaired CargoKit declaration: {path}")
        else:
            print(f"[PixelCraft] CargoKit Gradle 9 patch already applied: {path}")
        return

    imports = "import org.gradle.process.ExecOperations\nimport javax.inject.Inject\n"
    if "import org.gradle.process.ExecOperations" not in text:
        first_class = text.find("\nclass ")
        first_abstract_class = text.find("\nabstract class ")
        candidates = [i for i in (first_class, first_abstract_class) if i >= 0]
        insert_at = min(candidates) if candidates else -1
        if insert_at < 0:
            print("ERROR: Could not locate CargoKit class declarations.", file=sys.stderr)
            raise SystemExit(1)
        text = text[:insert_at] + "\n" + imports + text[insert_at:]

    class_pattern = re.compile(
        r"(?m)^(?:abstract\s+)?class\s+CargoKitBuildTask\s+extends\s+DefaultTask\s*\{"
    )
    match = class_pattern.search(text)
    if match is None:
        print("ERROR: Could not locate CargoKitBuildTask declaration.", file=sys.stderr)
        raise SystemExit(1)

    new_class = "abstract class CargoKitBuildTask extends DefaultTask {"
    text = text[: match.start()] + new_class + text[match.end() :]

    inject = """

    // Gradle 9 replacement for the removed Project.exec API.
    @Inject
    abstract ExecOperations getExecOperations()
"""
    if "abstract ExecOperations getExecOperations()" not in text:
        text = text.replace(new_class, new_class + inject, 1)

    count = text.count("project.exec {")
    if count == 0:
        print(
            "ERROR: No project.exec calls found; CargoKit template may have changed.",
            file=sys.stderr,
        )
        raise SystemExit(1)
    text = text.replace("project.exec {", "execOperations.exec {")

    if not backup.exists():
        backup.write_text(original, encoding="utf-8")
    path.write_text(text, encoding="utf-8")

    print(f"[PixelCraft] Patched {path} for Gradle 9 ({count} exec call(s)).")
    print(f"[PixelCraft] Original backup: {backup}")


def main() -> None:
    patch_cargokit_gradle()
    patch_android_plugin()


if __name__ == "__main__":
    main()
