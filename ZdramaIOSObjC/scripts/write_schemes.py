#!/usr/bin/env python3
"""Write shared schemes after xcodegen. xcodegen 2.46 does not emit them."""
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
pbx = root / "ZdramaObjC.xcodeproj" / "project.pbxproj"
dest = root / "ZdramaObjC.xcodeproj" / "xcshareddata" / "xcschemes"
if not pbx.exists():
    sys.exit("run xcodegen generate first")
text = pbx.read_text()
ids = {}
for match in re.finditer(
    r"([A-F0-9]{24}) /\* (ZdramaCoreObjC|ZdramaObjC|ZdramaCoreObjCTests) \*/ = \{\n\t\t\tisa = PBXNativeTarget;",
    text,
):
    ids[match.group(2)] = match.group(1)

def ref(blueprint, product):
    return f"""<BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{ids[blueprint]}"
               BuildableName = "{product}"
               BlueprintName = "{blueprint}"
               ReferencedContainer = "container:ZdramaObjC.xcodeproj">
            </BuildableReference>"""

def entry(blueprint, product):
    return f"""         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            {ref(blueprint, product)}
         </BuildActionEntry>"""

app = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "2600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
{entry("ZdramaCoreObjC", "libZdramaCoreObjC.a")}
{entry("ZdramaObjC", "ZdramaObjC.app")}
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables></Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      {ref("ZdramaObjC", "ZdramaObjC.app")}
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      {ref("ZdramaObjC", "ZdramaObjC.app")}
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug"></AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"></ArchiveAction>
</Scheme>
"""
core = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "2600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
{entry("ZdramaCoreObjC", "libZdramaCoreObjC.a")}
{entry("ZdramaCoreObjCTests", "ZdramaCoreObjCTests.xctest")}
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference skipped = "NO">
            {ref("ZdramaCoreObjCTests", "ZdramaCoreObjCTests.xctest")}
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "" selectedLauncherIdentifier = "Xcode.IDEFoundation.Launcher.PosixSpawn" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES"></LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES"></ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug"></AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"></ArchiveAction>
</Scheme>
"""
dest.mkdir(parents=True, exist_ok=True)
(dest / "ZdramaObjC.xcscheme").write_text(app)
(dest / "ZdramaCoreObjC.xcscheme").write_text(core)
print("wrote", dest)
