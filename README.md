# 테스 workmate — 내 업무 공간 (Codex)

테스 임직원 Codex 실습 교육 2교시 "지침과 스킬을 이해하고 내 업무 공간 만들기"에서 쓰는 워크스페이스입니다. 설치하면 최근에 쓰던 업무 파일을 이 PC 안에서 읽어 내 업무에 맞게 미리 세팅되고, 일할수록 기억·규칙·스킬이 쌓입니다.

- 분석은 내 PC의 Codex 안에서만 합니다. 파일을 외부로 보내지 않습니다.
- 최근 업무 파일이 거의 없으면 직무별 가상 예시 자료(연구소·CS·제조·품질·지원)로 세팅됩니다.
- 회사 위키(`memory/wiki/domain-context/`)는 공개 자료로 만든 것이라 사내 사정과 다를 수 있습니다.

## 설치

**Windows** — PowerShell을 열고 아래 한 줄을 붙여 넣습니다.

```powershell
irm https://raw.githubusercontent.com/axwith/tes-workmate/main/get.ps1 | iex
```

**Mac** — 터미널을 열고 아래 한 줄을 붙여 넣습니다.

```bash
curl -fsSL https://raw.githubusercontent.com/axwith/tes-workmate/main/install.sh | bash
```

설치가 끝나면(2~4분) 폴더가 열립니다(Windows `문서\tes-workmate`, Mac `~/Documents/tes-workmate`).

1. Codex 앱에서 그 폴더를 프로젝트로 엽니다.
2. "안녕하세요"라고 보내 보세요.

## 쓰는 법

- 업무를 시키면 결과와 함께 저장 위치를 알려 줍니다. 틀린 점은 말로 고쳐 주세요.
- "앞으로 항상 ○○" 하고 말하면 바로 규칙(`AGENTS.md` 5장)이 됩니다.
- 일이 끝나면 "정리해 줘"(`wrap`) — 기록이 남고 반복되는 일은 스킬 후보로 쌓입니다.
- 자주 하는 일은 "이 작업을 스킬로 만들어 줘"(`make-skill`).
- 자료를 더 넣고 싶으면 "최근 파일 더 모아 줘"(`collect`).
