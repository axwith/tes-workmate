# TES workmate 온보딩 상태 양식

> 설치된 개인 워크스페이스에서만 작성합니다. 공개 저장소에는 참가자의 실제 값이나 업무 자료를 넣지 않습니다.

```yaml
status: not_started
step: 1
scan_scope: null
work_scope: null
name: null
organization: null
current_work: null
recurring_work: null
report_target: null
tes_context: null
first_output_type: null
plan_path: null
plan_approved: false
output_path: null
```

상태 값은 `not_started` → `in_progress` → `plan_pending` → `approved` → `completed` 순서로 갱신합니다. `plan_approved: true`가 되기 전에는 첫 결과물을 생성하지 않습니다.
