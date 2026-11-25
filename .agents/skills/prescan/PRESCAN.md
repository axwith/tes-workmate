# 1차 세팅 절차 (스킬 아님 — AGENTS.md 시작 규칙과 설치기가 직접 따른다)


# prescan — 최근 파일 분석으로 사전 온보딩

사용자에게 묻지 않고 **한 번의 응답 안에서 6장 끝내기까지 모두 마친다.** "진행 중"으로 응답을 끝내지 않는다. 못 읽은 파일이 있어도 멈추지 말고 이름·위치로 판단해 계속한다. 중간에 확인을 구하지 않는다(사용자는 다른 창에서 실습 중일 수 있다). 원본 파일은 읽기만 한다.

**파일 쓰기 규칙**: 마크다운·JSON 파일은 파일 편집 도구(apply_patch 등)로 쓴다. PowerShell 문자열로 쓰지 않는다(`` `n``이 글자 그대로 남는 사고가 났다). 결과물·업무 폴더 README에 "추정입니다", "개인 자료", "확인 필요" 같은 단서 문구를 넣지 않는다. 확인할 것은 `memory/onboard-checklist.md`에만 적는다.

## 1. 환경 확인
- OS, 셸, `git`·`python`·`node` 유무, 오늘 날짜를 확인해 `memory/state.md`의 "환경"에 적는다.
- `memory/state.md`가 없으면 아래 틀로 만든다:
  ```
  # 상태
  prescan: 진행 중
  onboard: 미실행
  ## 환경
  ```

## 2. 최근 파일 찾기 (로컬 스크립트)
- **`memory/scan/recent-files.csv`가 있으면 `scan.ps1`을 절대 다시 돌리지 않는다**(설치기가 샌드박스 밖에서 이미 읽어 둔 것이 더 정확하다. 다시 돌리면 샌드박스 때문에 덜 읽히고 지정 폴더 설정도 사라진다). Codex 샌드박스 안에서는 문서·다운로드 폴더를 다 읽지 못한다. 없을 때만 아래를 실행한다(목록이 있으면 스크립트가 스스로 멈춘다).
- Windows: `powershell -NoProfile -ExecutionPolicy Bypass -File .agents/skills/prescan/scripts/scan.ps1`
  - 최근 30일 동안 열어 본 파일(Windows 최근 항목·Office 최근 문서), 문서·바탕화면·동기화 폴더에서 수정한 파일, 다운로드에 새로 받은 파일을 찾는다. 동기화 폴더는 이미 PC에 있는 것만 자동으로 찾는다: `OneDrive*`, OneDrive 레지스트리의 폴더 위치, SharePoint "동기화"로 생긴 `%USERPROFILE%\<회사명>\<사이트> - <라이브러리>`, 구글 드라이브.
  - 결과: `memory/scan/recent-files.csv`(목록), `memory/scan/text/`(문서 본문 앞부분), `memory/scan/scan-roots.csv`(본 폴더와 `기본`·`자동 발견`·`추가`·`제외` 표시).
  - 범위 설정은 `memory/scan/scan-config.json`이다(`include` 더할 폴더, `exclude` 뺄 폴더, `useDiscovered`, `maxDepth`, `extensions`, `skipOnlineOnly`). 설치 때 넣은 업무 폴더는 기본 검색에 더해진다. 요약은 `memory/env.md`의 "사전 스캔 범위".
  - 온라인 전용(클라우드에만 있는) 파일은 내려받지 않고 목록에만 남긴다. 그 행은 `copy`가 비고 `why`에 `online-only`가 붙는다. 이름·위치로 판단하고, 내용이 꼭 필요하면 사용자가 그 파일을 지정할 때만 연다.
- Mac: `python3 .agents/skills/prescan/scripts/scan.py` (같은 기준: Spotlight로 열어 본 파일, 문서·데스크탑·다운로드·클라우드 폴더에서 수정·새로 받은 파일. 결과 위치도 같다. `python3`이 없거나 PDF를 못 읽으면 Codex 런타임 Python `~/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3`으로 실행)
- Linux: 같은 기준으로 `find ~/Documents ~/Desktop ~/Downloads -type f -mtime -30`을 쓰고 같은 위치에 저장한다.
- 찾은 파일이 10개 미만이면 `-Days 90`(Mac: `--days 90`)으로 한 번 더 돌린다.
- **찾은 파일이 5개 미만이면** `.agents/skills/prescan/sample/pc/` 아래 파일을 직접 읽어 같은 절차로 진행한다. 결과물 제목·README에 "(예시 자료로 만든 세팅)"을 붙이고 state에 `sample 사용`을 적는다. 빈 화면으로 끝내지 않는다.

## 3. 읽고 묶기
- `recent-files.csv`에서 폴더 경로·파일 이름·확장자·날짜 패턴으로 **업무 단위**로 묶는다(예: "월간 품질 보고 — 매월 초 xlsx+pptx", "협력사 견적 비교").
- 묶음마다 `memory/scan/text/`의 본문을 읽어 무슨 일인지, 입력 자료, 결과물 형식, 주기, 보고 대상의 단서를 찾는다.
- `scan.ps1`이 PDF 본문도 뽑는다(Codex 앱에 함께 깔린 Python의 pypdf 사용). 그래도 본문이 없는 형식(hwp·구형 doc/xls·암호 걸린 파일) 중 중요해 보이는 것은 Codex의 documents·pdf·spreadsheets 스킬로 최대 10개까지 직접 열어 본다. 나머지는 이름과 위치로 판단한다.
- 찾은 파일은 거르지 않고 전부 분석한다(개인 자료인지 판단해 빼지 않는다). 업무로 묶기 어려운 파일도 "기타·참고" 묶음으로 지도에 넣는다. 고객사 교육담당자 확인(2026-11-20): 생성형 AI 사용 규정 없음, 로컬 Codex 안에서 처리.

> **사람 이름은 파일에서 추정하지 않는다.** 파일에는 작성자·결재자·협력사·고객 이름이 섞여 있어 다른 사람을 본인으로 잘못 넣을 수 있다. `profile.name`은 비우고, `profile.person`에는 직무만 쓴다. 이름·소속·보고 대상의 실명은 첫 작업 때 사용자에게 물어 채운다(AGENTS 0장).

> `references/`·`memory/wiki/`에 미리 들어 있는 자료(회사 위키·기준·용어집 등)가 있으면 먼저 읽고 분석에 쓴다. 그 파일은 지우거나 덮어쓰지 않는다(`references.criteria`·`glossary`에는 그중 이 사람 업무에 맞는 것만 옮겨 적는다).

## 4. 사전 온보딩 — 분석한 만큼 미리 적용한다
온보딩 때 사용자가 확인만 하면 되도록, 되돌리기 쉬운 것은 **지금 적용**한다. 파일은 직접 하나하나 쓰지 않고 **`memory/work-map.json` 하나를 쓴 뒤 `apply.ps1`을 실행**한다. 스크립트가 AGENTS.md 4장·업무 폴더 README·references·위키·확인 목록·대시보드를 한 번에 쓰고, 빠진 것이 있으면 `점검 실패`로 알려 준다. 실패 목록을 채워 JSON을 고치고 통과할 때까지 다시 실행한다.

1. 확신도가 가장 높은 업무 하나는 **실제 다음 회차 초안**을 먼저 만든다(지난 결과물과 같은 형식, 숫자는 자료에서 계산한 것만, 끝에 근거 파일). `reports/`에 저장.
2. `memory/work-map.md`에 업무 지도 표를 쓴다: `| 업무 | 단서 파일 | 입력 자료 | 결과물 | 주기 | 확신도 | 확인할 점 |`
3. `memory/work-map.json`을 편집 도구로 쓴다. 자료에서 추정한 값은 끝에 `(추정: 근거 파일)`, 못 찾은 값은 `(미확인)`.
```json
{"title":"내 업무 한눈에","date":"YYYY-MM-DD","days":30,"fileCount":55,
 "person":"직무(추정값 그대로)",
 "profile":{"name":"","person":"품질 담당 (추정: 월간 품질 보고·수입검사 자료)","report":"품질팀장 · 매월 첫째 주 (추정: 10월 보고)","works":"월간 품질 보고 → 20-operations/월간품질보고","criteria":"불량률=불량/검사, 차이는 %p (추정: 10월 보고)","terms":"(미확인)"},
 "folders":[{"path":"20-operations/월간품질보고","readme":"# 월간 품질 보고\n- 하는 일: …\n- 원본 위치: …\n- 주기: …\n- 결과물: …"}],
 "references":{"report-formats":"…","criteria":"…","glossary":"…"},
 "wiki":[{"category":"domain-context","title":"품질팀 업무 맥락","body":"…"},{"category":"preferences","title":"보고 형식","body":"…"}],
 "checklist":["보고 대상이 품질팀장 맞는지","팀 용어"],
 "works":[{"name":"월간 품질 보고","cycle":"매월","next":"12월 첫째 주","summary":"한 줄","output":"xlsx+pptx","files":["경로"]}],
 "upcoming":[{"when":"12/1(월)","what":"11월 품질 보고 제출"}],
 "activity":[{"date":"2026-11-03","count":4}],
 "drafts":[{"title":"11월 품질 보고 초안","href":"2026-11-20_11월-품질보고-초안.md","note":"지난달 형식 그대로"}]}
```
   `activity`는 `recent-files.csv`의 수정일별 파일 수, `drafts.href`는 reports 기준 상대 경로. `folders[].files`는 그 업무의 단서 파일 원래 경로(`recent-files.csv`의 path) — apply.ps1이 사본을 `<업무폴더>/자료/`로 복사한다. 원본 파일 내용이 필요하면 `recent-files.csv`의 `copy` 열(워크스페이스 안 사본)을 읽는다.
4. `powershell -NoProfile -ExecutionPolicy Bypass -File .agents/skills/prescan/scripts/apply.ps1` 실행 → `반영 완료`가 나올 때까지.
   Mac: `python3 .agents/skills/prescan/scripts/apply.py` (`python3`이 없으면 Codex 런타임 Python `~/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3`)
5. 반복 업무는 스킬 후보로, 파일 속 수정 흔적·지적 메모는 규칙 후보로 `memory/candidates.md`에 적는다(근거 = 파일 경로·날짜).
6. git 커밋은 하지 않는다(샌드박스가 `.git`을 막는다). 1시간마다 도는 자동 정리가 변경을 기록한다.

## 5. 끝내기 전 점검
- `apply.ps1`(Mac: `apply.py`)이 `반영 완료`를 냈다
- 만든 md 파일에 `` `n`` 같은 이스케이프 글자가 그대로 남아 있지 않다

## 6. 끝내기
- `memory/state.md`를 `prescan: 완료`로 바꾸고 찾은 파일 수·업무 수·만든 폴더 수를 적는다.
- `memory/daily/오늘.md`에 한 줄 기록.
- 사용자에게는 한 줄만: "준비됐어요. 돌아오시면 이어서 할게요." 분석 결과·파일 수·업무 목록을 늘어놓지 않는다(다음 대화에서 이미 아는 사람처럼 시작하기 위해). 자세한 내용은 `memory/state.md`에 남긴다.
- 파일 내용 원문을 대화에 길게 옮기지 않는다.
