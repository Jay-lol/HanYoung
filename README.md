# HanYoung

Caps Lock 한 키로 씹힘 없이 한영 전환하는 macOS 메뉴바 앱.
단일 Swift 파일로 만든 개인용 한영 전환 앱.

- **짧게 누르기**: 한영 전환. 키를 떼기 전, 누르는 즉시 전환
- **길게 누르기 (0.5초)**: 영문으로 돌아가 Caps Lock(대문자) 토글
- **메뉴바**: 현재 입력 소스 KO/EN 배지, 한국어/영어 선택, 활성화, 로그인 시 시작. macOS 기본 입력기 아이콘은 숨김

## 설치

macOS 13 이상, Xcode 또는 Command Line Tools 필요.

```sh
git clone https://github.com/Jay-lol/HanYoung.git
cd HanYoung
./build.sh install
```

1. 손쉬운 사용 권한 창이 뜨면 HanYoung을 허용 (메뉴바 아이콘이 흐리면 아직 권한이 없는 상태. 메뉴의 "⚠️ 손쉬운 사용 권한 필요"로 열 수 있음)
2. 메뉴바 아이콘 → **로그인 시 시작** 체크
3. Karabiner 등으로 Caps Lock을 바꿔둔 게 있으면 끄기

ad-hoc 서명이라 다시 빌드해서 설치할 때마다 손쉬운 사용 권한을 다시 허용해야 한다.

## 동작 방식

1. 모든 키보드의 Caps Lock을 HID `UserKeyMapping`으로 F19에 매핑 (3초마다 재적용, 종료 시 해제)
2. 시스템 단축키 "이전 입력 소스 선택"을 fn+F19로 설정
3. 이벤트 탭에서 F19 누름을 막고 F19 누름을 바로 보낸 뒤, 30ms 뒤에 뗌을 보냄

macOS 26에서 확인한 점:
- 누름·뗌을 1ms 간격으로 붙여 보내면 macOS가 단축키로 받지 않는다 → 30ms 간격
- F19 이벤트에 fn 플래그가 붙어 와서, 수식키 없는 F19 단축키로는 영어→한글 전환이 안 된다 → fn+F19

## 파일

| 파일 | 내용 |
|---|---|
| `HanYoung.swift` | 앱 전체 |
| `build.sh` | 빌드, `install`이면 /Applications에 설치 후 실행 |
| `IconGenerator.swift` | 앱 아이콘 생성 (`AppIcon.icns`) |
| `Bridge.h` | IOKit HID 헤더 |

## 라이선스

MIT
