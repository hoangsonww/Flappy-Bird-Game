#!/usr/bin/env python3
"""Regenerate `Flappy Bird.xcodeproj/project.pbxproj` from the files on disk.

Why this exists
---------------
The project has one app target and two test targets, and the directory a Swift
file lives in decides which target compiles it: `FlappyBird/` builds the app,
`FlappyBirdTests/` the unit tests, `FlappyBirdUITests/` the UI tests. Encoding
that rule in a script means:

* adding a file is `touch` + `make xcodegen` — no Xcode UI step, no merge
  conflicts in a 600-line pbxproj;
* CI can assert the checked-in project matches the file tree (`--check`);
* object IDs are derived from paths, so the output is byte-for-byte stable.

Usage
-----
    python3 scripts/generate_xcodeproj.py            # write the project
    python3 scripts/generate_xcodeproj.py --check    # exit 1 if out of date
"""

from __future__ import annotations

import argparse
import hashlib
import sys
from dataclasses import dataclass, field
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PROJECT_NAME = "Flappy Bird"
PROJECT_DIR = REPO_ROOT / f"{PROJECT_NAME}.xcodeproj"
PBXPROJ_PATH = PROJECT_DIR / "project.pbxproj"
SCHEME_PATH = PROJECT_DIR / "xcshareddata" / "xcschemes" / "FlappyBird.xcscheme"

APP_TARGET = "FlappyBird"
TEST_TARGET = "FlappyBirdTests"
UI_TEST_TARGET = "FlappyBirdUITests"
APP_DIR = REPO_ROOT / APP_TARGET
TEST_DIR = REPO_ROOT / TEST_TARGET
UI_TEST_DIR = REPO_ROOT / UI_TEST_TARGET

BUNDLE_ID = "com.hoangsonww.flappybird"
DEPLOYMENT_TARGET = "16.0"
SWIFT_VERSION = "5.0"
MARKETING_VERSION = "1.1.0"
CURRENT_PROJECT_VERSION = "2"

# Resources copied into the app bundle, in the order Xcode lists them.
APP_RESOURCES = ["Images.xcassets", "bird.atlas", "LaunchScreen.storyboard"]

FILE_TYPES = {
    ".swift": "sourcecode.swift",
    ".plist": "text.plist.xml",
    ".storyboard": "file.storyboard",
    ".xcassets": "folder.assetcatalog",
    ".atlas": "folder.skatlas",
    ".sks": "file.sks",
    ".md": "net.daringfireball.markdown",
}


def object_id(*parts: str) -> str:
    """Stable 24-character hex id derived from the object's identity."""
    digest = hashlib.md5("::".join(parts).encode("utf-8")).hexdigest()
    return digest[:24].upper()


def file_type(path: Path) -> str:
    return FILE_TYPES.get(path.suffix, "text")


@dataclass
class Group:
    """A PBXGroup mirroring one directory."""

    name: str
    path: str | None
    children_groups: dict[str, "Group"] = field(default_factory=dict)
    children_files: list[Path] = field(default_factory=list)
    # Pre-built children such as the localised storyboard's PBXVariantGroup.
    extra_children: list[tuple[str, str]] = field(default_factory=list)

    def ensure_child(self, name: str) -> "Group":
        if name not in self.children_groups:
            self.children_groups[name] = Group(name=name, path=name)
        return self.children_groups[name]


@dataclass(frozen=True)
class TestTarget:
    """One XCTest bundle.

    Unit tests are injected into the app (`TEST_HOST`); UI tests drive it from
    the outside (`TEST_TARGET_NAME`), which is the only difference that matters
    to the project file.
    """

    name: str
    directory: Path
    product_type: str
    settings: dict[str, str]


TEST_TARGETS = [
    TestTarget(
        name=TEST_TARGET,
        directory=TEST_DIR,
        product_type="com.apple.product-type.bundle.unit-test",
        settings={
            "BUNDLE_LOADER": f'"$(BUILT_PRODUCTS_DIR)/{APP_TARGET}.app/{APP_TARGET}"',
            "PRODUCT_BUNDLE_IDENTIFIER": f"{BUNDLE_ID}.tests",
            "TEST_HOST": '"$(BUNDLE_LOADER)"',
        },
    ),
    TestTarget(
        name=UI_TEST_TARGET,
        directory=UI_TEST_DIR,
        product_type="com.apple.product-type.bundle.ui-testing",
        settings={
            "PRODUCT_BUNDLE_IDENTIFIER": f"{BUNDLE_ID}.uitests",
            "TEST_TARGET_NAME": APP_TARGET,
        },
    ),
]


def test_object_ids(name: str) -> dict[str, str]:
    """Every object id a test target needs, keyed by role."""
    return {
        "target": object_id("target", name),
        "product": object_id("product", name),
        "sources": object_id("phase", name, "sources"),
        "frameworks": object_id("phase", name, "frameworks"),
        "resources": object_id("phase", name, "resources"),
        "config_list": object_id("configlist", name),
        "debug": object_id("config", name, "Debug"),
        "release": object_id("config", name, "Release"),
        "dependency": object_id("dependency", name),
        "proxy": object_id("proxy", name),
    }


def collect_swift(root: Path) -> list[Path]:
    """Every Swift file under `root`, sorted for deterministic output."""
    return sorted(p for p in root.rglob("*.swift") if p.is_file())


def build_group_tree(root_name: str, files: list[Path], base: Path, extra: list[str]) -> Group:
    """Turn a flat file list into a nested group structure."""
    root = Group(name=root_name, path=root_name)

    for absolute in files:
        relative = absolute.relative_to(base)
        node = root
        for part in relative.parts[:-1]:
            node = node.ensure_child(part)
        node.children_files.append(relative)

    for name in extra:
        root.children_files.append(Path(name))

    return root


def render_group(group: Group, target: str, lines: list[str], prefix: str = "") -> str:
    """Emit a PBXGroup (and its children) and return its object id."""
    group_path = f"{prefix}{group.name}"
    gid = object_id("group", target, group_path)

    child_entries: list[tuple[str, str]] = []

    for name in sorted(group.children_groups):
        child = group.children_groups[name]
        child_id = render_group(child, target, lines, prefix=f"{group_path}/")
        child_entries.append((child_id, name))

    for relative in sorted(group.children_files, key=lambda p: str(p)):
        file_id = object_id("file", target, str(relative))
        child_entries.append((file_id, relative.name))

    child_entries.extend(group.extra_children)

    lines.append(f"\t\t{gid} /* {group.name} */ = {{")
    lines.append("\t\t\tisa = PBXGroup;")
    lines.append("\t\t\tchildren = (")
    for child_id, name in child_entries:
        lines.append(f"\t\t\t\t{child_id} /* {name} */,")
    lines.append("\t\t\t);")
    if group.path is not None:
        lines.append(f"\t\t\tpath = {group.path};")
    else:
        lines.append(f"\t\t\tname = {group.name};")
    lines.append('\t\t\tsourceTree = "<group>";')
    lines.append("\t\t};")

    return gid


def quote(value: str) -> str:
    """Quote a pbxproj scalar when it is not a bare identifier."""
    safe = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./")
    if value and all(character in safe for character in value):
        return value
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def build_settings(common: dict[str, str], extra: dict[str, str]) -> list[str]:
    merged = {**common, **extra}
    return [f"\t\t\t\t{key} = {value};" for key, value in sorted(merged.items())]


def generate_pbxproj() -> str:
    app_swift = collect_swift(APP_DIR)
    test_swift = {test.name: collect_swift(test.directory) for test in TEST_TARGETS}

    if not app_swift:
        raise SystemExit(f"No Swift files found under {APP_DIR}")
    for test in TEST_TARGETS:
        if not test_swift[test.name]:
            raise SystemExit(f"No Swift files found under {test.directory}")

    app_group = build_group_tree(
        APP_TARGET,
        app_swift,
        APP_DIR,
        extra=APP_RESOURCES + ["Info.plist"],
    )
    test_groups = {
        test.name: build_group_tree(
            test.name, test_swift[test.name], test.directory, extra=["Info.plist"]
        )
        for test in TEST_TARGETS
    }

    # ── identifiers ────────────────────────────────────────────────────────────
    ids = {
        "project": object_id("project", PROJECT_NAME),
        "main_group": object_id("group", "root"),
        "products_group": object_id("group", "Products"),
        "app_target": object_id("target", APP_TARGET),
        "app_product": object_id("product", APP_TARGET),
        "app_sources": object_id("phase", APP_TARGET, "sources"),
        "app_frameworks": object_id("phase", APP_TARGET, "frameworks"),
        "app_resources": object_id("phase", APP_TARGET, "resources"),
        "project_config_list": object_id("configlist", "project"),
        "app_config_list": object_id("configlist", APP_TARGET),
        "project_debug": object_id("config", "project", "Debug"),
        "project_release": object_id("config", "project", "Release"),
        "app_debug": object_id("config", APP_TARGET, "Debug"),
        "app_release": object_id("config", APP_TARGET, "Release"),
    }
    test_ids = {test.name: test_object_ids(test.name) for test in TEST_TARGETS}

    lines: list[str] = []
    out = lines.append

    out("// !$*UTF8*$!")
    out("{")
    out("\tarchiveVersion = 1;")
    out("\tclasses = {")
    out("\t};")
    out("\tobjectVersion = 46;")
    out("\tobjects = {")

    # ── PBXBuildFile ──────────────────────────────────────────────────────────
    out("")
    out("/* Begin PBXBuildFile section */")
    for relative in app_swift:
        rel = relative.relative_to(APP_DIR)
        file_id = object_id("file", APP_TARGET, str(rel))
        build_id = object_id("build", APP_TARGET, str(rel))
        out(
            f"\t\t{build_id} /* {rel.name} in Sources */ = {{isa = PBXBuildFile; "
            f"fileRef = {file_id} /* {rel.name} */; }};"
        )
    for resource in APP_RESOURCES:
        file_id = object_id("file", APP_TARGET, resource)
        build_id = object_id("build", APP_TARGET, resource)
        out(
            f"\t\t{build_id} /* {resource} in Resources */ = {{isa = PBXBuildFile; "
            f"fileRef = {file_id} /* {resource} */; }};"
        )
    for test in TEST_TARGETS:
        for relative in test_swift[test.name]:
            rel = relative.relative_to(test.directory)
            file_id = object_id("file", test.name, str(rel))
            build_id = object_id("build", test.name, str(rel))
            out(
                f"\t\t{build_id} /* {rel.name} in Sources */ = {{isa = PBXBuildFile; "
                f"fileRef = {file_id} /* {rel.name} */; }};"
            )
    out("/* End PBXBuildFile section */")

    # ── PBXContainerItemProxy ────────────────────────────────────────────────
    out("")
    out("/* Begin PBXContainerItemProxy section */")
    for test in TEST_TARGETS:
        out(f"\t\t{test_ids[test.name]['proxy']} /* PBXContainerItemProxy */ = {{")
        out("\t\t\tisa = PBXContainerItemProxy;")
        out(f"\t\t\tcontainerPortal = {ids['project']} /* Project object */;")
        out("\t\t\tproxyType = 1;")
        out(f"\t\t\tremoteGlobalIDString = {ids['app_target']};")
        out(f"\t\t\tremoteInfo = {APP_TARGET};")
        out("\t\t};")
    out("/* End PBXContainerItemProxy section */")

    # ── PBXFileReference ─────────────────────────────────────────────────────
    out("")
    out("/* Begin PBXFileReference section */")
    out(
        f"\t\t{ids['app_product']} /* {APP_TARGET}.app */ = {{isa = PBXFileReference; "
        f"explicitFileType = wrapper.application; includeInIndex = 0; "
        f"path = {APP_TARGET}.app; sourceTree = BUILT_PRODUCTS_DIR; }};"
    )
    for test in TEST_TARGETS:
        out(
            f"\t\t{test_ids[test.name]['product']} /* {test.name}.xctest */ = "
            f"{{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; "
            f"includeInIndex = 0; path = {test.name}.xctest; "
            f"sourceTree = BUILT_PRODUCTS_DIR; }};"
        )

    def emit_file_reference(target: str, relative: Path) -> None:
        file_id = object_id("file", target, str(relative))
        out(
            f"\t\t{file_id} /* {relative.name} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = {file_type(relative)}; path = {quote(relative.name)}; "
            f'sourceTree = "<group>"; }};'
        )

    for relative in app_swift:
        emit_file_reference(APP_TARGET, relative.relative_to(APP_DIR))
    for resource in APP_RESOURCES + ["Info.plist"]:
        emit_file_reference(APP_TARGET, Path(resource))
    for test in TEST_TARGETS:
        for relative in test_swift[test.name]:
            emit_file_reference(test.name, relative.relative_to(test.directory))
        emit_file_reference(test.name, Path("Info.plist"))
    out("/* End PBXFileReference section */")

    # ── PBXFrameworksBuildPhase ──────────────────────────────────────────────
    out("")
    out("/* Begin PBXFrameworksBuildPhase section */")
    frameworks_phases = [(ids["app_frameworks"], APP_TARGET)]
    frameworks_phases += [(test_ids[t.name]["frameworks"], t.name) for t in TEST_TARGETS]
    for phase_id, label in frameworks_phases:
        out(f"\t\t{phase_id} /* Frameworks */ = {{")
        out("\t\t\tisa = PBXFrameworksBuildPhase;")
        out("\t\t\tbuildActionMask = 2147483647;")
        out("\t\t\tfiles = (")
        out("\t\t\t);")
        out("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        out("\t\t};")
    out("/* End PBXFrameworksBuildPhase section */")

    # ── PBXGroup ─────────────────────────────────────────────────────────────
    out("")
    out("/* Begin PBXGroup section */")
    group_lines: list[str] = []
    app_group_id = render_group(app_group, APP_TARGET, group_lines)
    test_group_ids = {
        test.name: render_group(test_groups[test.name], test.name, group_lines)
        for test in TEST_TARGETS
    }

    out(f"\t\t{ids['main_group']} = {{")
    out("\t\t\tisa = PBXGroup;")
    out("\t\t\tchildren = (")
    out(f"\t\t\t\t{app_group_id} /* {APP_TARGET} */,")
    for test in TEST_TARGETS:
        out(f"\t\t\t\t{test_group_ids[test.name]} /* {test.name} */,")
    out(f"\t\t\t\t{ids['products_group']} /* Products */,")
    out("\t\t\t);")
    out('\t\t\tsourceTree = "<group>";')
    out("\t\t\tusesTabs = 0;")
    out("\t\t};")

    out(f"\t\t{ids['products_group']} /* Products */ = {{")
    out("\t\t\tisa = PBXGroup;")
    out("\t\t\tchildren = (")
    out(f"\t\t\t\t{ids['app_product']} /* {APP_TARGET}.app */,")
    for test in TEST_TARGETS:
        out(f"\t\t\t\t{test_ids[test.name]['product']} /* {test.name}.xctest */,")
    out("\t\t\t);")
    out("\t\t\tname = Products;")
    out('\t\t\tsourceTree = "<group>";')
    out("\t\t};")

    lines.extend(group_lines)
    out("/* End PBXGroup section */")

    # ── PBXNativeTarget ──────────────────────────────────────────────────────
    out("")
    out("/* Begin PBXNativeTarget section */")
    out(f"\t\t{ids['app_target']} /* {APP_TARGET} */ = {{")
    out("\t\t\tisa = PBXNativeTarget;")
    out(
        f"\t\t\tbuildConfigurationList = {ids['app_config_list']} "
        f'/* Build configuration list for PBXNativeTarget "{APP_TARGET}" */;'
    )
    out("\t\t\tbuildPhases = (")
    out(f"\t\t\t\t{ids['app_sources']} /* Sources */,")
    out(f"\t\t\t\t{ids['app_frameworks']} /* Frameworks */,")
    out(f"\t\t\t\t{ids['app_resources']} /* Resources */,")
    out("\t\t\t);")
    out("\t\t\tbuildRules = (")
    out("\t\t\t);")
    out("\t\t\tdependencies = (")
    out("\t\t\t);")
    out(f"\t\t\tname = {APP_TARGET};")
    out(f"\t\t\tproductName = {APP_TARGET};")
    out(f"\t\t\tproductReference = {ids['app_product']} /* {APP_TARGET}.app */;")
    out('\t\t\tproductType = "com.apple.product-type.application";')
    out("\t\t};")

    for test in TEST_TARGETS:
        tid = test_ids[test.name]
        out(f"\t\t{tid['target']} /* {test.name} */ = {{")
        out("\t\t\tisa = PBXNativeTarget;")
        out(
            f"\t\t\tbuildConfigurationList = {tid['config_list']} "
            f'/* Build configuration list for PBXNativeTarget "{test.name}" */;'
        )
        out("\t\t\tbuildPhases = (")
        out(f"\t\t\t\t{tid['sources']} /* Sources */,")
        out(f"\t\t\t\t{tid['frameworks']} /* Frameworks */,")
        out(f"\t\t\t\t{tid['resources']} /* Resources */,")
        out("\t\t\t);")
        out("\t\t\tbuildRules = (")
        out("\t\t\t);")
        out("\t\t\tdependencies = (")
        out(f"\t\t\t\t{tid['dependency']} /* PBXTargetDependency */,")
        out("\t\t\t);")
        out(f"\t\t\tname = {test.name};")
        out(f"\t\t\tproductName = {test.name};")
        out(f"\t\t\tproductReference = {tid['product']} /* {test.name}.xctest */;")
        out(f'\t\t\tproductType = "{test.product_type}";')
        out("\t\t};")
    out("/* End PBXNativeTarget section */")

    # ── PBXProject ───────────────────────────────────────────────────────────
    out("")
    out("/* Begin PBXProject section */")
    out(f"\t\t{ids['project']} /* Project object */ = {{")
    out("\t\t\tisa = PBXProject;")
    out("\t\t\tattributes = {")
    out("\t\t\t\tBuildIndependentTargetsInParallel = YES;")
    out("\t\t\t\tLastSwiftUpdateCheck = 1600;")
    out("\t\t\t\tLastUpgradeCheck = 1600;")
    out('\t\t\t\tORGANIZATIONNAME = "Son Nguyen";')
    out("\t\t\t\tTargetAttributes = {")
    out(f"\t\t\t\t\t{ids['app_target']} = {{")
    out("\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;")
    out("\t\t\t\t\t};")
    for test in TEST_TARGETS:
        out(f"\t\t\t\t\t{test_ids[test.name]['target']} = {{")
        out("\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;")
        out(f"\t\t\t\t\t\tTestTargetID = {ids['app_target']};")
        out("\t\t\t\t\t};")
    out("\t\t\t\t};")
    out("\t\t\t};")
    out(
        f"\t\t\tbuildConfigurationList = {ids['project_config_list']} "
        f'/* Build configuration list for PBXProject "{PROJECT_NAME}" */;'
    )
    out('\t\t\tcompatibilityVersion = "Xcode 12.0";')
    out("\t\t\tdevelopmentRegion = en;")
    out("\t\t\thasScannedForEncodings = 0;")
    out("\t\t\tknownRegions = (")
    out("\t\t\t\ten,")
    out("\t\t\t\tBase,")
    out("\t\t\t);")
    out(f"\t\t\tmainGroup = {ids['main_group']};")
    out(f"\t\t\tproductRefGroup = {ids['products_group']} /* Products */;")
    out('\t\t\tprojectDirPath = "";')
    out('\t\t\tprojectRoot = "";')
    out("\t\t\ttargets = (")
    out(f"\t\t\t\t{ids['app_target']} /* {APP_TARGET} */,")
    for test in TEST_TARGETS:
        out(f"\t\t\t\t{test_ids[test.name]['target']} /* {test.name} */,")
    out("\t\t\t);")
    out("\t\t};")
    out("/* End PBXProject section */")

    # ── PBXResourcesBuildPhase ───────────────────────────────────────────────
    out("")
    out("/* Begin PBXResourcesBuildPhase section */")
    out(f"\t\t{ids['app_resources']} /* Resources */ = {{")
    out("\t\t\tisa = PBXResourcesBuildPhase;")
    out("\t\t\tbuildActionMask = 2147483647;")
    out("\t\t\tfiles = (")
    for resource in APP_RESOURCES:
        build_id = object_id("build", APP_TARGET, resource)
        out(f"\t\t\t\t{build_id} /* {resource} in Resources */,")
    out("\t\t\t);")
    out("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    out("\t\t};")
    for test in TEST_TARGETS:
        out(f"\t\t{test_ids[test.name]['resources']} /* Resources */ = {{")
        out("\t\t\tisa = PBXResourcesBuildPhase;")
        out("\t\t\tbuildActionMask = 2147483647;")
        out("\t\t\tfiles = (")
        out("\t\t\t);")
        out("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        out("\t\t};")
    out("/* End PBXResourcesBuildPhase section */")

    # ── PBXSourcesBuildPhase ─────────────────────────────────────────────────
    out("")
    out("/* Begin PBXSourcesBuildPhase section */")
    out(f"\t\t{ids['app_sources']} /* Sources */ = {{")
    out("\t\t\tisa = PBXSourcesBuildPhase;")
    out("\t\t\tbuildActionMask = 2147483647;")
    out("\t\t\tfiles = (")
    for relative in app_swift:
        rel = relative.relative_to(APP_DIR)
        build_id = object_id("build", APP_TARGET, str(rel))
        out(f"\t\t\t\t{build_id} /* {rel.name} in Sources */,")
    out("\t\t\t);")
    out("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    out("\t\t};")
    for test in TEST_TARGETS:
        out(f"\t\t{test_ids[test.name]['sources']} /* Sources */ = {{")
        out("\t\t\tisa = PBXSourcesBuildPhase;")
        out("\t\t\tbuildActionMask = 2147483647;")
        out("\t\t\tfiles = (")
        for relative in test_swift[test.name]:
            rel = relative.relative_to(test.directory)
            build_id = object_id("build", test.name, str(rel))
            out(f"\t\t\t\t{build_id} /* {rel.name} in Sources */,")
        out("\t\t\t);")
        out("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        out("\t\t};")
    out("/* End PBXSourcesBuildPhase section */")

    # ── PBXTargetDependency ──────────────────────────────────────────────────
    out("")
    out("/* Begin PBXTargetDependency section */")
    for test in TEST_TARGETS:
        tid = test_ids[test.name]
        out(f"\t\t{tid['dependency']} /* PBXTargetDependency */ = {{")
        out("\t\t\tisa = PBXTargetDependency;")
        out(f"\t\t\ttarget = {ids['app_target']} /* {APP_TARGET} */;")
        out(f"\t\t\ttargetProxy = {tid['proxy']} /* PBXContainerItemProxy */;")
        out("\t\t};")
    out("/* End PBXTargetDependency section */")

    # ── XCBuildConfiguration ─────────────────────────────────────────────────
    project_common = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "CLANG_WARN_BOOL_CONVERSION": "YES",
        "CLANG_WARN_CONSTANT_CONVERSION": "YES",
        "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
        "CLANG_WARN_EMPTY_BODY": "YES",
        "CLANG_WARN_ENUM_CONVERSION": "YES",
        "CLANG_WARN_INFINITE_RECURSION": "YES",
        "CLANG_WARN_INT_CONVERSION": "YES",
        "CLANG_WARN_UNREACHABLE_CODE": "YES",
        "COPY_PHASE_STRIP": "NO",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
        "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
        "GCC_WARN_UNDECLARED_SELECTOR": "YES",
        "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
        "GCC_WARN_UNUSED_FUNCTION": "YES",
        "GCC_WARN_UNUSED_VARIABLE": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
        "SDKROOT": "iphoneos",
        "SWIFT_VERSION": SWIFT_VERSION,
        "TARGETED_DEVICE_FAMILY": '"1,2"',
    }

    app_common = {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": CURRENT_PROJECT_VERSION,
        "DEVELOPMENT_TEAM": '""',
        "ENABLE_PREVIEWS": "YES",
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": f"{APP_TARGET}/Info.plist",
        "INFOPLIST_KEY_CFBundleDisplayName": '"Flappy Bird"',
        "INFOPLIST_KEY_LSApplicationCategoryType": '"public.app-category.games"',
        "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks"',
        "MARKETING_VERSION": MARKETING_VERSION,
        "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
        "PRODUCT_NAME": '"$(TARGET_NAME)"',
        "SWIFT_EMIT_LOC_STRINGS": "YES",
    }

    def test_settings(test: TestTarget) -> dict[str, str]:
        return {
            "CODE_SIGN_STYLE": "Automatic",
            "CURRENT_PROJECT_VERSION": CURRENT_PROJECT_VERSION,
            "GENERATE_INFOPLIST_FILE": "NO",
            "INFOPLIST_FILE": f"{test.name}/Info.plist",
            "MARKETING_VERSION": MARKETING_VERSION,
            "PRODUCT_NAME": '"$(TARGET_NAME)"',
            **test.settings,
        }

    out("")
    out("/* Begin XCBuildConfiguration section */")

    configurations = [
        (
            ids["project_debug"],
            "Debug",
            project_common,
            {
                "DEBUG_INFORMATION_FORMAT": "dwarf",
                "ENABLE_TESTABILITY": "YES",
                "GCC_DYNAMIC_NO_PIC": "NO",
                "GCC_OPTIMIZATION_LEVEL": "0",
                "GCC_PREPROCESSOR_DEFINITIONS": '"DEBUG=1 $(inherited)"',
                "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
                "ONLY_ACTIVE_ARCH": "YES",
                "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
                "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
            },
        ),
        (
            ids["project_release"],
            "Release",
            project_common,
            {
                "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
                "ENABLE_NS_ASSERTIONS": "NO",
                "MTL_ENABLE_DEBUG_INFO": "NO",
                "SWIFT_COMPILATION_MODE": "wholemodule",
                "SWIFT_OPTIMIZATION_LEVEL": '"-O"',
                "VALIDATE_PRODUCT": "YES",
            },
        ),
        (ids["app_debug"], "Debug", app_common, {}),
        (ids["app_release"], "Release", app_common, {}),
    ]
    for test in TEST_TARGETS:
        settings = test_settings(test)
        configurations.append((test_ids[test.name]["debug"], "Debug", settings, {}))
        configurations.append((test_ids[test.name]["release"], "Release", settings, {}))

    for config_id, name, common, extra in configurations:
        out(f"\t\t{config_id} /* {name} */ = {{")
        out("\t\t\tisa = XCBuildConfiguration;")
        out("\t\t\tbuildSettings = {")
        lines.extend(build_settings(common, extra))
        out("\t\t\t};")
        out(f"\t\t\tname = {name};")
        out("\t\t};")
    out("/* End XCBuildConfiguration section */")

    # ── XCConfigurationList ──────────────────────────────────────────────────
    out("")
    out("/* Begin XCConfigurationList section */")
    config_lists = [
        (ids["project_config_list"], f'PBXProject "{PROJECT_NAME}"', ids["project_debug"], ids["project_release"]),
        (ids["app_config_list"], f'PBXNativeTarget "{APP_TARGET}"', ids["app_debug"], ids["app_release"]),
    ]
    config_lists += [
        (
            test_ids[test.name]["config_list"],
            f'PBXNativeTarget "{test.name}"',
            test_ids[test.name]["debug"],
            test_ids[test.name]["release"],
        )
        for test in TEST_TARGETS
    ]
    for list_id, label, debug_id, release_id in config_lists:
        out(f"\t\t{list_id} /* Build configuration list for {label} */ = {{")
        out("\t\t\tisa = XCConfigurationList;")
        out("\t\t\tbuildConfigurations = (")
        out(f"\t\t\t\t{debug_id} /* Debug */,")
        out(f"\t\t\t\t{release_id} /* Release */,")
        out("\t\t\t);")
        out("\t\t\tdefaultConfigurationIsVisible = 0;")
        out("\t\t\tdefaultConfigurationName = Release;")
        out("\t\t};")
    out("/* End XCConfigurationList section */")

    out("\t};")
    out(f"\trootObject = {ids['project']} /* Project object */;")
    out("}")

    return "\n".join(lines) + "\n"


SCHEME_TEMPLATE = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{app_target_id}"
               BuildableName = "{app_target}.app"
               BlueprintName = "{app_target}"
               ReferencedContainer = "container:{project_name}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
{testables}      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_target_id}"
            BuildableName = "{app_target}.app"
            BlueprintName = "{app_target}"
            ReferencedContainer = "container:{project_name}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_target_id}"
            BuildableName = "{app_target}.app"
            BlueprintName = "{app_target}"
            ReferencedContainer = "container:{project_name}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""


TESTABLE_TEMPLATE = """         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{test_target_id}"
               BuildableName = "{test_target}.xctest"
               BlueprintName = "{test_target}"
               ReferencedContainer = "container:{project_name}.xcodeproj">
            </BuildableReference>
         </TestableReference>
"""


def generate_scheme() -> str:
    testables = "".join(
        TESTABLE_TEMPLATE.format(
            test_target=test.name,
            test_target_id=object_id("target", test.name),
            project_name=PROJECT_NAME,
        )
        for test in TEST_TARGETS
    )
    return SCHEME_TEMPLATE.format(
        app_target=APP_TARGET,
        app_target_id=object_id("target", APP_TARGET),
        project_name=PROJECT_NAME,
        testables=testables,
    )


WORKSPACE_DATA = """<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "self:">
   </FileRef>
</Workspace>
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify the checked-in project matches the files on disk",
    )
    args = parser.parse_args()

    outputs = {
        PBXPROJ_PATH: generate_pbxproj(),
        SCHEME_PATH: generate_scheme(),
        PROJECT_DIR / "project.xcworkspace" / "contents.xcworkspacedata": WORKSPACE_DATA,
    }

    if args.check:
        stale = [
            path.relative_to(REPO_ROOT)
            for path, content in outputs.items()
            if not path.exists() or path.read_text() != content
        ]
        if stale:
            print("✖ Xcode project is out of date:")
            for path in stale:
                print(f"    {path}")
            print("\n  Run: make xcodegen")
            return 1
        print("✓ Xcode project matches the files on disk")
        return 0

    for path, content in outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    app_count = len(collect_swift(APP_DIR))
    counts = ", ".join(
        f"{len(collect_swift(test.directory))} {test.name} sources" for test in TEST_TARGETS
    )
    print(
        f"✓ Wrote {PBXPROJ_PATH.relative_to(REPO_ROOT)} "
        f"({app_count} app sources, {counts})"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
