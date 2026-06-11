# 창 투명도 조절기 (Window Transparency Adjuster)

다른 프로그램 창을 **반투명하게** 만들어 주는 가벼운 Windows 유틸리티.

![screenshot](docs/screenshot.png)

## ✨ 기능
- 🎯 **과녁 드래그**로 원하는 창 선택 (손잡이 없는 finder 도구)
- 🎚️ 슬라이더로 **불투명도 5~100%** 실시간 조절
- ↩️ 적용한 창에 과녁을 다시 놓으면 **그 창만 복원** (토글)
- 🧹 **모두 복원** 버튼으로 한 번에 원래대로
- 📦 **단일 exe**, 설치 불필요 (Windows 10/11 내장 기능만 사용)

## ⬇️ 다운로드 & 실행
1. [Releases](../../releases) 에서 `WindowTransparencyAdjuster-1.0.0.exe` (또는 `.zip`) 다운로드
2. 더블클릭으로 실행
3. 처음 실행 시 SmartScreen 경고가 뜨면 **추가 정보 → 실행** (서명 없는 개인 빌드라 정상입니다)

## 🖱️ 사용법
1. 과녁(둥근 아이콘)을 마우스로 끌어, 투명하게 만들 창 위에서 손 떼기
2. 슬라이더로 투명도 조절 (실시간 적용)
3. 같은 창에 과녁을 다시 놓으면 그 창만 복원 · **모두 복원**으로 전체 복원

> 관리자 권한으로 실행된 창에 적용하려면, 이 프로그램도 우클릭 → **관리자 권한으로 실행** 하세요.

## 🛠️ 소스에서 빌드
본체는 PowerShell 스크립트 [`TransparencyTool.ps1`](TransparencyTool.ps1) 하나입니다.
`.ps1`을 바로 실행해도 되고, [ps2exe](https://github.com/MScholtes/PS2EXE)로 exe를 만들 수 있습니다:

```powershell
Install-Module ps2exe -Scope CurrentUser
Invoke-ps2exe -inputFile TransparencyTool.ps1 -outputFile "창 투명도 조절기.exe" `
    -iconFile lens.ico -noConsole -STA -version 1.0.0.0
```

## ⚙️ 동작 원리
Win32 `SetLayeredWindowAttributes` (+ `WS_EX_LAYERED` 확장 스타일)로 대상 창에 알파값을 적용합니다.
불투명도 %는 `alpha = round(% × 255 / 100)` 로 변환됩니다. 별도 라이브러리·설치 없이
Windows에 내장된 PowerShell + WinForms + Win32 API만 사용합니다.

아이콘 디자인 후보는 [docs/icon-candidates.html](docs/icon-candidates.html) 참고.

## 📄 라이선스
[MIT](LICENSE)
