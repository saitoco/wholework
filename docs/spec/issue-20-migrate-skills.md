# Issue #20: skills: Migrate from private repo with English conversion

## auto レトロスペクティブ

### 実行サマリー
| # | タイトル | ルート | 結果 | 備考 |
|---|---------|--------|------|------|
| #21 | Simple skills (merge, code, auto, verify) | pr (M) | SUCCESS | spec→code→review(light)→merge→verify。PR番号抽出バグで手動リカバリ |
| #22 | Core workflow skills (issue, spec, review) | pr (L) | SUCCESS | spec→code→review(full)→merge→verify。PR番号抽出バグで手動リカバリ。#23と並列実行 |
| #23 | Utility skills (triage, audit, doc) | pr (M) | SUCCESS | phase/readyラベル未付与で2回中断→手動設定後に再実行で成功。#22と並列実行 |

### 並列実行の問題
- #22 と #23 を並列実行したが、#23 は `phase/ready` ラベルが付与されないまま code フェーズに進み2回中断。手動でラベル設定後に再実行して解決
- `run-auto-sub.sh` の PR 番号抽出バグ（`gh pr list --head` がグロブパターン非対応）は #6 から継続する既知の問題。全3件で発生し手動リカバリ

### 改善提案
- `run-auto-sub.sh` の `phase/ready` ラベル付与漏れ: spec 完了後に `phase/ready` に遷移する処理が一部のケースで動作しない。spec → code の間でラベル状態を確認・補正するロジックの追加が必要
- PR 番号抽出バグの修正は既に #6 の auto レトロスペクティブで提案済み（`gh pr list --head` → `gh pr list --json` フィルタリング方式への変更）

## issue レトロスペクティブ

### 判断経緯
- wholework の既存 6 skills がスタブ（各 8-9 行）であることを確認し、全て本体で置換する方針を決定
- 21 ファイル = XL のため sub-issue 分割を実施。依存関係に基づき A(シンプル) → B(コア)+C(ユーティリティ) の 3 分割

### 重要な方針決定
- scripts/modules/agents と同様の方針を踏襲: 英語化 + 機会主義的簡素化 + migration-notes 記録
- B(issue,spec,review) と C(triage,audit,doc) は並列実行可能（両方とも A にのみ依存）

### 受け入れ条件の変更理由
- 親 Issue の個別条件を各 sub-issue に再配分し、親には cross-cutting 条件（全スキル validate-skill-syntax PASS）のみ残した
