# Issue #312: auto/verify: Auto Retrospective を全 route に拡張し orchestration 異常を skill-proposals へ繋ぐ

## Overview

`/auto` Step 4a の Auto Retrospective は現在 XL route のみ実行される。M/L/patch route で `run-code.sh` 等の shell wrapper が失敗し親セッションが手動回復した場合、その異常情報がどの phase retrospective にも残らず `/verify` Step 13 の skill-proposals パイプラインに繋がらない問題がある。

本 Issue では：
1. `/auto` Step 4a を全 route に拡張し、orchestration 異常検出時に `## Auto Retrospective` セクションを Spec に書く
2. `/verify` Step 13 で `## Auto Retrospective > ### Improvement Proposals` を明示的に scan 対象として文書化する
3. 手動回復時の hand-off 手順を `/auto` SKILL.md に明文化する

## Changed Files

- `skills/auto/SKILL.md`: Step 4a heading から "(XL route only)" を削除; "XL のみ実行" ルールを全 route での orchestration 異常検出ベースのルールに変更; M/L/patch 向け `### Orchestration Anomalies` テンプレートを追加; Step 6 "On Failure" に手動回復時 hand-off 注記を追加
- `skills/verify/SKILL.md`: Step 10 の Auto Retrospective 抽出注記から "XL route retrospective" 限定表現を削除; Step 13 の `### Improvement Proposals` 抽出対象に Auto Retrospective が全 route で対象となることを明記

## Implementation Steps

1. `skills/auto/SKILL.md` Step 4a 改修 (→ AC1, AC2):
   - `### Step 4a: Auto Retrospective (XL route only)` を `### Step 4a: Auto Retrospective` に変更
   - "**Skip this step for all routes other than XL.**" を以下のルールに置き換える:
     - **XL route**: 従来通り全 sub-issue の Execution Summary / Parallel Execution Issues / Improvement Proposals を記録
     - **M/L/patch route**: parent が以下のいずれかを検出した場合のみ Spec 末尾に `## Auto Retrospective` セクションを追加:
       (a) shell wrapper (`run-code.sh`, `run-auto-sub.sh` 等) が exit 非 0 だが後続状態を手動回復した  
       (b) 本来自動遷移すべき phase を parent が手動実行した  
       (c) `/auto` が元の仕様と異なる挙動で完走した  
     - 異常なしの場合はセクションを作らない
   - M/L/patch route 向けテンプレートを追記 (Execution Summary テーブルに Phase/Route/Result/Notes 列; `### Orchestration Anomalies`; `### Improvement Proposals`)
   - Spec 未存在時 (XS patch route 等): Step 4b パターンに準じ、`# Issue #$NUMBER: $TITLE` ヘッダ付きで Spec を新規作成してから追記する

2. `skills/auto/SKILL.md` Step 6 "On Failure" に手動回復 hand-off 注記を追加 (→ AC4):
   - "stop processing and output the stopped banner" の直前に注記を追加:
     「parent session が wrapper 失敗を手動回復して次 phase に進む場合は、先に Step 4a の手順に従って Spec の `## Auto Retrospective > ### Orchestration Anomalies` と `### Improvement Proposals` に異常内容と改善提案を追記してから次 phase を実行すること」

3. `skills/verify/SKILL.md` Step 10・Step 13 更新 (→ AC3):
   - Step 10 の情報収集リスト中 "Extract `## Auto Retrospective` section (result of `/auto` XL route retrospective; skip if not present)" → "(present when orchestration anomalies were detected on any route; skip if not present)" に変更
   - Step 13 の `### Improvement Proposals` 抽出説明に、`## Auto Retrospective` は全 route での異常検出時に生成されることを明記し、XL 限定という誤解を与える表現があれば削除

## Verification

### Pre-merge

- <!-- verify: rubric "skills/auto/SKILL.md Step 4a 'Auto Retrospective' is documented to fire on all routes (XS/S/M/L/XL) when orchestration anomalies are detected, not only for XL, with an 'Orchestration Anomalies' subsection in the template" --> `/auto` Step 4a が全 route で orchestration 異常検出時に作動するよう仕様更新されている
- <!-- verify: grep "Orchestration Anomalies" "skills/auto/SKILL.md" --> `skills/auto/SKILL.md` に `### Orchestration Anomalies` サブセクションのテンプレートが追加されている
- <!-- verify: rubric "skills/verify/SKILL.md Step 13 documents that `## Auto Retrospective > ### Improvement Proposals` is also scanned alongside per-phase retrospectives for auto-filed improvement issues" --> `/verify` Step 13 が Auto Retrospective を scan 対象に含める仕様に更新されている
- <!-- verify: rubric "skills/auto/SKILL.md describes the handshake for manual recovery from shell wrapper failures: parent session appends anomaly details and improvement proposals to the Spec's Auto Retrospective before continuing to subsequent phases" --> parent session の手動回復時 hand-off が明文化されている

### Post-merge

- 意図的に shell wrapper を失敗させた上で `/auto` の手動回復 → `/verify` 実行を行い、Auto Retrospective の Improvement Proposals から Issue が自動起票されることを確認

## Notes

- XS patch route での Spec 未存在時は Step 4b パターン（Issue Retrospective 有無に関わらず `# Issue #N: title` ヘッダ付きで新規作成）に準じる
- `/verify` Step 13 はすでに "auto" を scan 対象として列挙しているが、Step 10 の注記が "XL route retrospective" に限定されており、M/L/patch で Auto Retrospective が存在しなかったため機能していなかった。今回の Step 4a 拡張で `/auto` が Spec に書くようになることで既存の Step 13 scan が自動的に機能する
- Auto-resolve: Issue body では「XS/S patch route での Spec 未存在時の挙動」を自動解決済み（Step 4b パターンに準じて新規作成）として記録
