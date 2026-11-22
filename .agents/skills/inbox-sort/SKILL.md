---
name: inbox-sort
description: 00-inbox에 있는 파일을 업무 폴더로 정리한다. "인박스 정리", "받은 파일 정리해 줘", "00-inbox 폴더별로 나눠 줘", "들어온 자료 제자리에", collect 다음 단계에 쓴다.
---

# inbox-sort — 받은 자료를 업무 폴더로

1. `00-inbox/` 아래 파일 목록을 만든다(하위 폴더 포함, `_목록.csv`가 있으면 원래 위치도 참고).
2. 파일마다 이름·형식으로 먼저 정하고, 이름만으로 애매한 파일은 **앞부분 내용을 읽어** 정한다(docx·pptx·xlsx·hwpx는 `prescan/scripts/scan.ps1`(Mac: `scan.py`)과 같은 방식, PDF는 `prescan/scripts/pdftext.py`를 Codex 런타임 Python으로). 미분류는 최소로 줄인다. 기준은 `AGENTS.md` 2장 저장 규칙과 4장 업무 지도.
   - 반복 업무 자료 → `20-operations/<업무>/`
   - 기간 있는 일 → `10-projects/<과제>/`
   - 양식·기준값 문서 → `references/`
   - 참고 자료 → `50-resources/`
   - 판단이 안 서면 `00-inbox/_미분류/`에 두고 이유를 적는다
3. 옮긴 뒤 결과 표(파일 → 옮긴 곳 → 이유)를 `reports/`에 CSV로 남기고, 묶음별 건수만 보여 준다. 따로 확인받지 않는다(원본은 그대로이고 inbox 복사본만 옮기므로 되돌리기 쉽다). 사용자가 고치라고 하면 고친다.
4. 옮긴 뒤 새 업무 폴더가 생겼으면 `AGENTS.md` 4장과 `memory/work-map.md`에 반영한다.
5. 정리 기준이 사용자 교정으로 바뀌면 `wrap` 때 규칙 후보로 남긴다.
