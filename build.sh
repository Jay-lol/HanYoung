#!/bin/bash
# HanYoung.app을 빌드한다. `install`을 주면 /Applications에 설치하고 실행한다.
# 아이콘은 Tools/IconGenerator.swift로 만든다: swift Tools/IconGenerator.swift build/AppIcon.iconset && iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
# ad-hoc 서명이라 빌드할 때마다 앱 식별값이 바뀌므로, 설치 시 예전 손쉬운 사용 권한을 지우고 새로 허용받는다.
set -euo pipefail
cd "$(dirname "$0")"
# Command Line Tools 16.4는 macOS 26에서 모듈맵 충돌로 빌드가 깨져, Xcode가 있으면 Xcode 툴체인을 쓴다.
if [[ -z ${DEVELOPER_DIR:-} && -d /Applications/Xcode.app ]]; then export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; fi
app=build/HanYoung.app
rm -rf build && mkdir -p "$app/Contents/MacOS"
xcrun swiftc -O -import-objc-header Sources/Bridge.h $(find Sources -name "*.swift") -framework AppKit -framework IOKit -framework ServiceManagement \
  -target "$(uname -m)-apple-macos13.0" -o "$app/Contents/MacOS/HanYoung"
cp Resources/Info.plist "$app/Contents/Info.plist"
mkdir -p "$app/Contents/Resources" && cp Resources/AppIcon.icns "$app/Contents/Resources/"
codesign --force --sign - --identifier dev.jay.hanyoung "$app"
if [[ ${1:-} == install ]]; then
  pkill -x HanYoung || true
  rm -rf /Applications/HanYoung.app && cp -R "$app" /Applications/
  tccutil reset Accessibility dev.jay.hanyoung >/dev/null 2>&1 || true  # 처음 설치면 지울 항목이 없다
  open /Applications/HanYoung.app
fi
echo "Built $app"
