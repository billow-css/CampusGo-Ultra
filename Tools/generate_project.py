#!/usr/bin/env python3
"""Regenerate the dependency-free Xcode project after adding Swift files."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
SIGNING_FILE = ROOT / "Signing.local.json"
SIGNING = json.loads(SIGNING_FILE.read_text()) if SIGNING_FILE.exists() else {}
PROJECT = ROOT / "CampusSchedule.xcodeproj"
PROJECT.mkdir(exist_ok=True)
objects = {}

def uid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()

def add(object_key, isa, **fields):
    key = uid(object_key)
    objects[key] = {"isa": isa, **fields}
    return key

def ref(path, kind):
    return add("file:" + path, "PBXFileReference", lastKnownFileType=kind, path=path, sourceTree="<group>")

groups = []
files = {}
for folder in ["App", "Shared", "Widget", "Configuration", "Resources"]:
    children = []
    for file in sorted((ROOT / folder).iterdir()):
        if not file.is_file():
            continue
        relative = str(file.relative_to(ROOT))
        kind = {".swift": "sourcecode.swift", ".entitlements": "text.plist.entitlements",
                ".icns": "image.icns", ".png": "image.png"}.get(file.suffix, "text.plist.xml")
        files[relative] = ref(relative, kind)
        children.append(files[relative])
    groups.append(add("group:" + folder, "PBXGroup", name=folder, children=children, sourceTree="<group>"))

frameworks = {}
for name in ["SwiftUI", "EventKit", "WidgetKit"]:
    frameworks[name] = add("framework:" + name, "PBXFileReference", lastKnownFileType="wrapper.framework",
        name=name + ".framework", path="System/Library/Frameworks/" + name + ".framework", sourceTree="SDKROOT")
groups.append(add("group:frameworks", "PBXGroup", name="Frameworks", children=list(frameworks.values()), sourceTree="<group>"))

appProduct = add("product:app", "PBXFileReference", explicitFileType="wrapper.application", path="CampusGo Ultra.app", sourceTree="BUILT_PRODUCTS_DIR")
widgetProduct = add("product:widget", "PBXFileReference", explicitFileType="wrapper.app-extension", path="CampusGoUltraWidget.appex", sourceTree="BUILT_PRODUCTS_DIR")
productGroup = add("group:products", "PBXGroup", name="Products", children=[appProduct, widgetProduct], sourceTree="<group>")
groups.append(productGroup)
mainGroup = add("group:main", "PBXGroup", children=groups, sourceTree="<group>")

def configs(name, base):
    refs = []
    for mode in ["Debug", "Release"]:
        settings = {**base}
        if mode == "Debug":
            settings.update(SWIFT_OPTIMIZATION_LEVEL="-Onone", DEBUG_INFORMATION_FORMAT="dwarf", SWIFT_ACTIVE_COMPILATION_CONDITIONS="DEBUG")
        else:
            settings.update(SWIFT_COMPILATION_MODE="wholemodule", SWIFT_OPTIMIZATION_LEVEL="-O", DEBUG_INFORMATION_FORMAT="dwarf-with-dsym")
        refs.append(add("config:" + name + ":" + mode, "XCBuildConfiguration", name=mode, buildSettings=settings))
    return add("configs:" + name, "XCConfigurationList", buildConfigurations=refs, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")

projectConfigs = configs("project", {"MACOSX_DEPLOYMENT_TARGET": "14.0", "SDKROOT": "macosx", "SWIFT_VERSION": "5.0",
    "CLANG_ENABLE_MODULES": "YES", "ENABLE_USER_SCRIPT_SANDBOXING": "YES", "CLANG_ENABLE_OBJC_ARC": "YES"})

def target(name, sourceFolders, bundle, plist, entitlements, product, productType, dependencies=None, extraPhases=None):
    builds = [add("build:" + name + ":" + path, "PBXBuildFile", fileRef=file) for path, file in files.items()
        if path.endswith(".swift") and path.split("/")[0] in sourceFolders]
    sources = add("sources:" + name, "PBXSourcesBuildPhase", buildActionMask=2147483647, files=builds, runOnlyForDeploymentPostprocessing=0)
    linked = [add("link:" + name + ":" + fw, "PBXBuildFile", fileRef=frameworks[fw])
        for fw in (["SwiftUI", "WidgetKit", "EventKit"] if name == "CampusSchedule" else ["SwiftUI", "WidgetKit"])]
    frameworkPhase = add("links:" + name, "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=linked, runOnlyForDeploymentPostprocessing=0)
    resourceFiles = [add("resource:" + name + ":" + path, "PBXBuildFile", fileRef=file)
        for path, file in files.items() if path.startswith("Resources/") and (name == "CampusSchedule" or path == "Resources/NUISTGo.icns")]
    resources = add("resources:" + name, "PBXResourcesBuildPhase", buildActionMask=2147483647, files=resourceFiles, runOnlyForDeploymentPostprocessing=0)
    settings = {"PRODUCT_NAME": ("CampusGo Ultra" if name == "CampusSchedule" else "CampusGoUltraWidget"), "PRODUCT_BUNDLE_IDENTIFIER": bundle, "INFOPLIST_FILE": plist,
        "CODE_SIGN_ENTITLEMENTS": entitlements, "CODE_SIGN_STYLE": SIGNING.get("style", "Automatic"), "DEVELOPMENT_TEAM": SIGNING.get("teamID", ""),
        "NUISTGO_APP_GROUP": SIGNING.get("appGroup", "group.com.campusschedule.shared"),
        "REGISTER_APP_GROUPS": "NO" if SIGNING.get("appGroup", "").startswith(SIGNING.get("teamID", "!") + ".") else "YES",
        "GENERATE_INFOPLIST_FILE": "NO", "SUPPORTED_PLATFORMS": "macosx", "ENABLE_HARDENED_RUNTIME": "YES",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/../Frameworks"], "SWIFT_EMIT_LOC_STRINGS": "YES"}
    if SIGNING.get("identity"):
        settings["CODE_SIGN_IDENTITY"] = SIGNING["identity"]
    if name.endswith("Widget"):
        settings.update(SKIP_INSTALL="YES", APPLICATION_EXTENSION_API_ONLY="YES", LD_RUNPATH_SEARCH_PATHS=["$(inherited)", "@executable_path/../Frameworks", "@executable_path/../../../../Frameworks"])
    return add("target:" + name, "PBXNativeTarget", buildConfigurationList=configs(name, settings),
        buildPhases=[sources, frameworkPhase, resources] + (extraPhases or []), buildRules=[], dependencies=dependencies or [],
        name=name, productName=name, productReference=product, productType=productType)

widget = target("CampusScheduleWidget", ["Shared", "Widget"], "com.campusschedule.mac.widget",
    "Configuration/Widget-Info.plist", "Configuration/Widget.entitlements", widgetProduct, "com.apple.product-type.app-extension")
proxy = add("widget:proxy", "PBXContainerItemProxy", containerPortal=uid("project"), proxyType=1,
    remoteGlobalIDString=widget, remoteInfo="CampusScheduleWidget")
dependency = add("widget:dependency", "PBXTargetDependency", target=widget, targetProxy=proxy)
embed = add("widget:embed", "PBXBuildFile", fileRef=widgetProduct, settings={"ATTRIBUTES": ["RemoveHeadersOnCopy", "CodeSignOnCopy"]})
embedPhase = add("widget:embedPhase", "PBXCopyFilesBuildPhase", buildActionMask=2147483647, dstPath="", dstSubfolderSpec=13,
    files=[embed], name="Embed App Extensions", runOnlyForDeploymentPostprocessing=0)
app = target("CampusSchedule", ["Shared", "App"], "com.campusschedule.mac", "Configuration/App-Info.plist",
    "Configuration/App.entitlements", appProduct, "com.apple.product-type.application", [dependency], [embedPhase])
add("project", "PBXProject", attributes={"LastUpgradeCheck": "1600", "BuildIndependentTargetsInParallel": "YES"},
    buildConfigurationList=projectConfigs, compatibilityVersion="Xcode 14.0", developmentRegion="zh_CN", hasScannedForEncodings=0,
    knownRegions=["zh_CN", "en", "Base"], mainGroup=mainGroup, productRefGroup=productGroup, projectDirPath="", projectRoot="", targets=[app, widget])

def emit(value, indent=0):
    if isinstance(value, dict):
        return "{\n" + "".join("\t" * (indent+1) + json.dumps(str(k)) + " = " + emit(v, indent+1) + ";\n" for k,v in value.items()) + "\t" * indent + "}"
    if isinstance(value, list):
        return "(\n" + "".join("\t" * (indent+1) + emit(v, indent+1) + ",\n" for v in value) + "\t" * indent + ")"
    return str(value) if isinstance(value, int) else json.dumps(value, ensure_ascii=False)

(PROJECT / "project.pbxproj").write_text("// !$*UTF8*$!\n" + emit({"archiveVersion":1,"classes":{},"objectVersion":56,"objects":objects,"rootObject":uid("project")}) + "\n")
schemes = PROJECT / "xcshareddata/xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
for title, demo in [("CampusGo Ultra", False),("CampusGo Ultra Demo", True),("NUISTGo", False),("NUISTGo Demo", True),("CampusSchedule", False),("CampusSchedule Demo", True)]:
    buildable = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app}" BuildableName="CampusGo Ultra.app" BlueprintName="CampusSchedule" ReferencedContainer="container:CampusSchedule.xcodeproj"/>'
    args = '<CommandLineArguments><CommandLineArgument argument="--demo" isEnabled="YES"/></CommandLineArguments>' if demo else ''
    (schemes / (title + ".xcscheme")).write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildable}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables/></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable}</BuildableProductRunnable>{args}</LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(PROJECT)
