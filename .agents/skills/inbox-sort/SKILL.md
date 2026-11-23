---
name: inbox-sort
description: 자료를 00-inbox로 모으고 업무 폴더로 정리한다. "최근 파일 더 가져와", "이 폴더 자료도 넣어 줘", "자료 추가할게", "다운로드 폴더 것도 봐 줘"(모으기)와 "인박스 정리", "받은 파일 정리해 줘", "00-inbox 폴더별로 나눠 줘", "들어온 자료 제자리에"(정리)에 쓴다.
---

# inbox-sort — 자료 모으기와 업무 폴더 정리

사용자가 자료를 더 넣어 달라고 하면 1장(모으기)부터, 이미 `00-inbox/`에 있는 것을 정리하라고 하면 2장부터 한다. 모은 뒤에는 이어서 2장까지 한다.

## 1. 모으기 (원본은 그대로, 복사만)

무엇을 모을지는 사용자 말에서 정한다. 없으면 번호로 묻는다.
1. 최근 N일 파일 전부 (기본 30일) — `memory/scan/recent-files.csv`를 새로 만들고 그 목록을 복사
2. 특정 폴더 — 사용자가 말한 경로 아래 문서 파일
3. 특정 파일 — 사용자가 끌어다 놓거나 경로를 준 것

- 샌드박스 밖 폴더를 읽어야 하므로 이 스크립트는 **권한 상승을 요청해 실행**한다(앱에서 승인 창이 한 번 뜬다).
- Windows: `powershell -NoProfile -ExecutionPolicy Bypass -File .agents/skills/inbox-sort/scripts/collect.ps1 -Days 30` 또는 `-From "경로"`.
- Mac: `python3 .agents/skills/inbox-sort/scripts/collect.py --days 30` 또는 `--from "경로"` (복사 뒤 Finder로 연다).
- `00-inbox/YYYY-MM-DD/` 아래로 복사하고 `00-inbox/YYYY-MM-DD/_목록.csv`(원래 위치·수정일)를 남긴다.
- 복사 뒤 탐색기로 그 폴더를 열어 주고 "빼고 싶은 파일은 지우고 알려 주세요"라고 한 번 말한다. 기다리지 않아도 된다.

## 2. 업무 폴더로 정리

1. `00-inbox/` 아래 파일 목록을 만든다(하위 폴더 포함, `_목록.csv`가 있으면 원래 위치도 참고).
2. 파일마다 이름·형식으로 먼저 정하고, 이름만으로 애매한 파일은 **앞부분 내용을 읽어** 정한다(docx·pptx·xlsx·hwpx는 `prescan/scripts/scan.ps1`(Mac: `scan.py`)과 같은 방식, PDF는 `prescan/scripts/pdftext.py`를 Codex 런타임 Python으로). 미분류는 최소로 줄인다. 기준은 `AGENTS.md` 2장 저장 규칙과 4장 업무 지도.
   - 반복 업무 자료 → `20-operations/<업무>/`
   - 기간 있는 일 → `10-projects/<과제>/`
   - 양식·기준값 문서 → `references/`
   - 참고 자료 → `50-resources/`
   - 판단이 안 서면 `00-inbox/_미분류/`에 두고 이유를 적는다
3. 옮긴 뒤 결과 표(파일 → 옮긴 곳 → 이유)를 `reports/`에 CSV로 남기고, 묶음별 건수만 보여 준다. 따로 확인받지 않는다(원본은 그대로이고 inbox 복사본만 옮기므로 되돌리기 쉽다). 사용자가 고치라고 하면 고친다.

## 3. 업무 지도 보강

- 새 업무 폴더가 생겼거나 새 자료로 업무·단서가 늘었으면 `AGENTS.md` 4장과 `memory/work-map.md`에 반영하고, 바뀐 점은 `onboard`의 개편 제안 형식으로 보여 준다.
- 정리 기준이 사용자 교정으로 바뀌면 `wrap` 때 규칙 후보로 남긴다.
