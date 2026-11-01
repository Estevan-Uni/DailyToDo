#!/usr/bin/env python3
"""Generate/check the local Xcode UI-test entry without an external generator.

This checks source membership, plist/XML/JSON structure and reference integrity;
it deliberately does not claim that Xcode compiled or executed the tests.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import uuid
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
PROJECT = "DailyToDo.xcodeproj"
APP = "DailyToDoValidation"
SUITE = "DailyToDoUITests"
SCHEME = "DailyToDo-UI"
LIBRARIES = ["TodoDomain", "TodoPersistence", "TodoInteraction", "TodoServices"]


def identifier(name):
    return hashlib.sha1(("DailyToDo-Xcode-" + name).encode()).hexdigest()[:24].upper()


def openstep(value, level=0):
    indent = "\t" * level
    if isinstance(value, dict):
        lines = ["{"]
        for key, child in value.items():
            lines.append(indent + "\t" + json.dumps(key) + " = " + openstep(child, level + 1) + ";")
        return "\n".join(lines) + "\n" + indent + "}"
    if isinstance(value, list):
        return "(\n" + "".join(indent + "\t" + openstep(child, level + 1) + ",\n" for child in value) + indent + ")"
    return json.dumps(value, ensure_ascii=False)


def artifacts():
    objects = {}

    def put(seed, kind, **fields):
        key = identifier(seed)
        if key in objects:
            raise ValueError("Duplicate generated object: " + seed)
        objects[key] = dict(isa=kind, **fields)
        return key

    project_id, app_id, suite_id = map(identifier, ["project", "app", "suite"])
    group_id, products_id = map(identifier, ["group-main", "group-products"])
    package_id = put("package", "XCLocalSwiftPackageReference", relativePath=".")
    app_product = put("app-product", "PBXFileReference", explicitFileType="wrapper.application", includeInIndex="0", path=APP + ".app", sourceTree="BUILT_PRODUCTS_DIR")
    test_product = put("test-product", "PBXFileReference", explicitFileType="wrapper.cfbundle", includeInIndex="0", path=SUITE + ".xctest", sourceTree="BUILT_PRODUCTS_DIR")

    def source_phase(paths, name):
        references, builds = [], []
        for path in paths:
            reference = put("file-" + path, "PBXFileReference", lastKnownFileType="sourcecode.swift", name=Path(path).name, path=path, sourceTree="SOURCE_ROOT")
            references.append(reference)
            builds.append(put("build-" + path, "PBXBuildFile", fileRef=reference))
        phase = put("sources-" + name, "PBXSourcesBuildPhase", buildActionMask="2147483647", files=builds, runOnlyForDeploymentPostprocessing="0")
        return references, phase

    app_sources = sorted(str(path.relative_to(ROOT)) for path in (ROOT / "Sources/DailyToDo").rglob("*.swift"))
    test_sources = sorted(str(path.relative_to(ROOT)) for path in (ROOT / "UITests").glob("*.swift"))
    if not app_sources or not test_sources:
        raise ValueError("App/UI-test Swift sources are missing")
    app_refs, app_sources_phase = source_phase(app_sources, "app")
    test_refs, test_sources_phase = source_phase(test_sources, "tests")
    package_products, framework_builds = [], []
    for name in LIBRARIES:
        product = put("library-" + name, "XCSwiftPackageProductDependency", package=package_id, productName=name)
        package_products.append(product)
        framework_builds.append(put("framework-" + name, "PBXBuildFile", productRef=product))
    app_frameworks = put("app-frameworks", "PBXFrameworksBuildPhase", buildActionMask="2147483647", files=framework_builds, runOnlyForDeploymentPostprocessing="0")
    test_frameworks = put("test-frameworks", "PBXFrameworksBuildPhase", buildActionMask="2147483647", files=[], runOnlyForDeploymentPostprocessing="0")
    app_resources = put("app-resources", "PBXResourcesBuildPhase", buildActionMask="2147483647", files=[], runOnlyForDeploymentPostprocessing="0")
    test_resources = put("test-resources", "PBXResourcesBuildPhase", buildActionMask="2147483647", files=[], runOnlyForDeploymentPostprocessing="0")
    proxy = put("app-proxy", "PBXContainerItemProxy", containerPortal=project_id, proxyType="1", remoteGlobalIDString=app_id, remoteInfo=APP)
    dependency = put("app-dependency", "PBXTargetDependency", target=app_id, targetProxy=proxy)

    version = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())
    common = dict(SDKROOT="macosx", MACOSX_DEPLOYMENT_TARGET="14.0", SWIFT_VERSION="6.0", CLANG_ENABLE_MODULES="YES", CLANG_ENABLE_OBJC_ARC="YES", SWIFT_STRICT_CONCURRENCY="complete", ENABLE_USER_SCRIPT_SANDBOXING="YES")
    app_settings = dict(PRODUCT_NAME=APP, PRODUCT_BUNDLE_IDENTIFIER="local.tododesktop.xcuitest", INFOPLIST_FILE="UITests/Host-Info.plist", GENERATE_INFOPLIST_FILE="NO", CODE_SIGN_ENTITLEMENTS="Resources/DailyToDo.entitlements", ENABLE_APP_SANDBOX="YES", CODE_SIGN_STYLE="Manual", CODE_SIGN_IDENTITY="-", SUPPORTED_PLATFORMS="macosx", MARKETING_VERSION=version["CFBundleShortVersionString"], CURRENT_PROJECT_VERSION=version["CFBundleVersion"], LD_RUNPATH_SEARCH_PATHS=["$(inherited)", "@executable_path/../Frameworks"])
    suite_settings = dict(PRODUCT_NAME="$(TARGET_NAME)", PRODUCT_BUNDLE_IDENTIFIER="local.tododesktop.xcuitests", GENERATE_INFOPLIST_FILE="YES", CODE_SIGN_STYLE="Manual", CODE_SIGN_IDENTITY="-", TEST_TARGET_NAME=APP, SUPPORTED_PLATFORMS="macosx", LD_RUNPATH_SEARCH_PATHS=["$(inherited)", "@executable_path/../Frameworks", "@loader_path/../Frameworks"])

    def configurations(name, base):
        configs = []
        for configuration in ["Debug", "Release"]:
            settings = dict(base)
            if configuration == "Debug":
                settings.update(SWIFT_OPTIMIZATION_LEVEL="-Onone", SWIFT_ACTIVE_COMPILATION_CONDITIONS="DEBUG", ENABLE_TESTABILITY="YES", ONLY_ACTIVE_ARCH="YES")
            else:
                settings.update(SWIFT_OPTIMIZATION_LEVEL="-O", SWIFT_COMPILATION_MODE="wholemodule")
            configs.append(put(name + "-" + configuration, "XCBuildConfiguration", name=configuration, buildSettings=settings))
        return put(name + "-configurations", "XCConfigurationList", buildConfigurations=configs, defaultConfigurationIsVisible="0", defaultConfigurationName="Release")

    project_configs = configurations("project", common)
    app_configs = configurations("app", app_settings)
    suite_configs = configurations("suite", suite_settings)
    put("app", "PBXNativeTarget", name=APP, productName=APP, productReference=app_product, productType="com.apple.product-type.application", buildConfigurationList=app_configs, buildPhases=[app_sources_phase, app_frameworks, app_resources], buildRules=[], dependencies=[], packageProductDependencies=package_products)
    put("suite", "PBXNativeTarget", name=SUITE, productName=SUITE, productReference=test_product, productType="com.apple.product-type.bundle.ui-testing", buildConfigurationList=suite_configs, buildPhases=[test_sources_phase, test_frameworks, test_resources], buildRules=[], dependencies=[dependency])
    app_group = put("group-app", "PBXGroup", name="Production App Sources", children=app_refs, sourceTree="<group>")
    info_ref = put("host-info", "PBXFileReference", lastKnownFileType="text.plist.xml", path="UITests/Host-Info.plist", sourceTree="SOURCE_ROOT")
    test_group = put("group-tests", "PBXGroup", name="UI Tests", children=test_refs + [info_ref], sourceTree="<group>")
    put("group-products", "PBXGroup", name="Products", children=[app_product, test_product], sourceTree="<group>")
    put("group-main", "PBXGroup", children=[app_group, test_group, products_id], sourceTree="<group>")
    put("project", "PBXProject", attributes={"LastUpgradeCheck": "1600", "TargetAttributes": {app_id: {"CreatedOnToolsVersion": "16.0", "ProvisioningStyle": "Manual"}, suite_id: {"CreatedOnToolsVersion": "16.0", "TestTargetID": app_id}}}, buildConfigurationList=project_configs, compatibilityVersion="Xcode 14.0", developmentRegion="en", knownRegions=["en", "Base", "zh-Hans"], mainGroup=group_id, productRefGroup=products_id, projectDirPath="", projectRoot="", targets=[app_id, suite_id], packageReferences=[package_id])
    project = dict(archiveVersion="1", classes={}, objectVersion="56", objects=objects, rootObject=project_id)

    def check_references(value):
        if isinstance(value, str) and re.fullmatch(r"[A-F0-9]{24}", value) and value not in objects:
            raise ValueError("Unknown generated reference: " + value)
        if isinstance(value, dict):
            for child in value.values():
                check_references(child)
        if isinstance(value, list):
            for child in value:
                check_references(child)
    check_references(project)

    scheme = ET.Element("Scheme", LastUpgradeVersion="1600", version="1.7")
    build = ET.SubElement(scheme, "BuildAction", parallelizeBuildables="YES", buildImplicitDependencies="YES")
    entries = ET.SubElement(build, "BuildActionEntries")
    def buildable(parent, target, name, product):
        ET.SubElement(parent, "BuildableReference", BuildableIdentifier="primary", BlueprintIdentifier=target, BuildableName=product, BlueprintName=name, ReferencedContainer="container:" + PROJECT)
    for target, name, product, other in [(app_id, APP, APP + ".app", "YES"), (suite_id, SUITE, SUITE + ".xctest", "NO")]:
        entry = ET.SubElement(entries, "BuildActionEntry", buildForTesting="YES", buildForRunning=other, buildForProfiling=other, buildForArchiving=other, buildForAnalyzing=other)
        buildable(entry, target, name, product)
    tests = ET.SubElement(scheme, "TestAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB", selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", shouldUseLaunchSchemeArgsEnv="YES")
    plans = ET.SubElement(tests, "TestPlans")
    ET.SubElement(plans, "TestPlanReference", reference="container:UITests/DailyToDo.xctestplan", default="YES")
    launch = ET.SubElement(scheme, "LaunchAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB", selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", launchStyle="0", useCustomWorkingDirectory="NO", ignoresPersistentStateOnLaunch="YES", debugDocumentVersioning="YES", debugServiceExtension="internal", allowLocationSimulation="NO")
    runnable = ET.SubElement(launch, "BuildableProductRunnable", runnableDebuggingMode="0")
    buildable(runnable, app_id, APP, APP + ".app")
    # Running the scheme manually is isolated too, without synthesizing user data.
    arguments = ET.SubElement(launch, "CommandLineArguments")
    ET.SubElement(arguments, "CommandLineArgument", argument="--ui-test=xcode-manual", isEnabled="YES")
    profile = ET.SubElement(scheme, "ProfileAction", buildConfiguration="Release", shouldUseLaunchSchemeArgsEnv="YES", savedToolIdentifier="", useCustomWorkingDirectory="NO", debugDocumentVersioning="YES")
    profile_runnable = ET.SubElement(profile, "BuildableProductRunnable", runnableDebuggingMode="0")
    buildable(profile_runnable, app_id, APP, APP + ".app")
    ET.SubElement(scheme, "AnalyzeAction", buildConfiguration="Debug")
    ET.SubElement(scheme, "ArchiveAction", buildConfiguration="Release", revealArchiveInOrganizer="YES")
    ET.indent(scheme, space="   ")
    plan = {"configurations": [{"id": str(uuid.uuid5(uuid.NAMESPACE_URL, "local.tododesktop.ui-default")).upper(), "name": "Local Mac", "options": {}}], "defaultOptions": {"targetForVariableExpansion": {"containerPath": "container:" + PROJECT, "identifier": app_id, "name": APP}}, "testTargets": [{"parallelizable": False, "target": {"containerPath": "container:" + PROJECT, "identifier": suite_id, "name": SUITE}}], "version": 1}
    info = dict(CFBundleDisplayName="DailyToDo 界面验收", CFBundleName="$(PRODUCT_NAME)", CFBundleIdentifier="$(PRODUCT_BUNDLE_IDENTIFIER)", CFBundleExecutable="$(EXECUTABLE_NAME)", CFBundlePackageType="APPL", CFBundleShortVersionString="$(MARKETING_VERSION)", CFBundleVersion="$(CURRENT_PROJECT_VERSION)", LSMinimumSystemVersion="$(MACOSX_DEPLOYMENT_TARGET)", NSHighResolutionCapable=True, NSPrincipalClass="NSApplication")
    return {
        PROJECT + "/project.pbxproj": ("// !$*UTF8*$!\n" + openstep(project) + "\n").encode(),
        PROJECT + "/xcshareddata/xcschemes/" + SCHEME + ".xcscheme": ET.tostring(scheme, encoding="utf-8", xml_declaration=True) + b"\n",
        "UITests/DailyToDo.xctestplan": (json.dumps(plan, indent=2, ensure_ascii=False) + "\n").encode(),
        "UITests/Host-Info.plist": plistlib.dumps(info, sort_keys=False),
    }, project, app_sources, test_sources


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="reject stale artifacts; do not write")
    args = parser.parse_args()
    files, project, app_sources, test_sources = artifacts()
    for name, content in files.items():
        path = ROOT / name
        if args.check:
            if not path.exists() or path.read_bytes() != content:
                raise ValueError("Stale or missing generated file: " + name + "; run scripts/generate-xcode-project.py")
        else:
            path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(content)
    serialized = subprocess.check_output(["/usr/bin/plutil", "-convert", "json", "-o", "-", "--", str(ROOT / PROJECT / "project.pbxproj")])
    if json.loads(serialized) != project:
        raise ValueError("The native plist parser disagrees with the generated project")
    ET.fromstring(files[PROJECT + "/xcshareddata/xcschemes/" + SCHEME + ".xcscheme"])
    package = json.loads(subprocess.check_output(["swift", "package", "dump-package"], cwd=ROOT))
    names = {item["name"] for item in package["products"]}
    if not set(LIBRARIES).issubset(names):
        raise ValueError("The local package is missing an Xcode library product")
    print(f"Xcode entry structure checked: {len(app_sources)} production Swift files, {len(test_sources)} UI-test files, {len(project['objects'])} references. Xcode build/tests not executed.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"Xcode entry check failed: {error}", file=sys.stderr)
        raise SystemExit(2)
