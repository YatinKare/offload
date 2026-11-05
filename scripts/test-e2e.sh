#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SIMULATOR_ID="${1:-}"
if [[ $# -gt 0 ]]; then shift; fi
if [[ -z "$SIMULATOR_ID" ]]; then
  SIMULATOR_ID="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; devices=[d for group in json.load(sys.stdin)["devices"].values() for d in group if d.get("isAvailable") and "iPhone" in d["name"]]; devices.sort(key=lambda d: d["state"] != "Booted"); print(devices[0]["udid"] if devices else "")')"
fi
if [[ -z "$SIMULATOR_ID" ]]; then
  echo "Install an iPhone simulator runtime in Xcode, or pass a simulator UUID." >&2
  exit 1
fi
mkdir -p build
xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b
xcodebuild -project Offload.xcodeproj -target OffloadUITests -sdk iphonesimulator CONFIGURATION_BUILD_DIR="$PWD/build/manual" CODE_SIGNING_ALLOWED=NO build > build/test-build.log 2>&1
python3 - <<'PY'
import os, plistlib
base=os.path.abspath('build/manual')
config={'OffloadUITests':{'TestBundlePath':base+'/OffloadUITests-Runner.app/PlugIns/OffloadUITests.xctest','TestHostPath':base+'/OffloadUITests-Runner.app','TestHostBundleIdentifier':'dev.offload.OffloadUITests.xctrunner','UITargetAppPath':base+'/Offload.app','UITargetAppBundleIdentifier':'dev.offload.app','IsUITestBundle':True,'IsAppHostedTestBundle':True,'EnvironmentVariables':{},'TestingEnvironmentVariables':{'DYLD_FRAMEWORK_PATH':'__PLATFORMS__/iPhoneSimulator.platform/Developer/Library/Frameworks','DYLD_LIBRARY_PATH':'__PLATFORMS__/iPhoneSimulator.platform/Developer/usr/lib'},'SystemAttachmentLifetime':'keepAlways','UserAttachmentLifetime':'keepAlways'},'__xctestrun_metadata__':{'FormatVersion':1}}
with open('build/Manual.xctestrun','wb') as f: plistlib.dump(config,f)
PY
# Force fresh bundles: test-without-building can cache unchanged bundle versions.
xcrun simctl uninstall "$SIMULATOR_ID" dev.offload.app 2>/dev/null || true
xcrun simctl uninstall "$SIMULATOR_ID" dev.offload.OffloadUITests.xctrunner 2>/dev/null || true
xcrun simctl install "$SIMULATOR_ID" "$PWD/build/manual/Offload.app"
xcrun simctl install "$SIMULATOR_ID" "$PWD/build/manual/OffloadUITests-Runner.app"
RESULT="build/E2E-$(date +%Y%m%d-%H%M%S).xcresult"
xcodebuild test-without-building -xctestrun build/Manual.xctestrun -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -parallel-testing-enabled NO -resultBundlePath "$RESULT" "$@"
echo "Results: $RESULT"
