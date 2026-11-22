---
name: collect
description: 분석할 자료를 더 넣고 싶을 때 00-inbox로 모은다. "최근 파일 더 가져와", "이 폴더 자료도 넣어 줘", "자료 추가"에 쓴다. 모은 뒤 inbox-sort와 업무 지도 보강까지 이어서 한다.
---

# collect — 자료를 inbox로 모아 분석 보강

## 1. 무엇을 모을지
사용자 말에서 정한다. 없으면 번호로 묻는다.
1. 최근 N일 파일 전부 (기본 30일) — `memory/scan/recent-files.csv`를 새로 만들고 그 목록을 복사
2. 특정 폴더 — 사용자가 말한 경로 아래 문서 파일
3. 특정 파일 — 사용자가 끌어다 놓거나 경로를 준 것

## 2. 복사 (원본은 그대로)
- 샌드박스 밖 폴더를 읽어야 하므로 이 스크립트는 **권한 상승을 요청해 실행**한다(앱에서 승인 창이 한 번 뜬다).
- Windows: `powershell -NoProfile -ExecutionPolicy Bypass -File .agents/skills/collect/scripts/collect.ps1 -Days 30` 또는 `-From "경로"`.
- Mac: `python3 .agents/skills/collect/scripts/collect.py --days 30` 또는 `--from "경로"` (복사 뒤 Finder로 연다).
- `00-inbox/YYYY-MM-DD/` 아래로 복사하고 `00-inbox/YYYY-MM-DD/_목록.csv`(원래 위치·수정일)를 남긴다.
- 복사 뒤 탐색기로 그 폴더를 열어 주고 "빼고 싶은 파일은 지우고 알려 주세요"라고 한 번 말한다. 기다리지 않아도 된다.

## 3. 이어서
- `inbox-sort`로 업무 폴더에 정리한다.
- 새 자료로 `memory/work-map.md`에 업무·단서를 보강하고, 바뀐 점이 있으면 `onboard`의 개편 제안 형식으로 보여 준다.
