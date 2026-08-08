# Issue #1289: get-auto-session-report: Route mix の route 導出を post-spec Size 再評価後の実績イベントへ変更

## Overview

`scripts/get-auto-session-report.sh` の `Route mix` メトリクスは、`sub_start` イベントの `size` フィールド (spec フェーズ前の Size) から route (patch/pr/xl) を導出しているため、`/spec` が post-spec で Size を降格・昇格させた Issue では、集計上の route と実際に実行された route が食い違う。導出元を `code-pr` / `code-patch` phase イベントの有無 (実際に実行されたフェーズ) へ変更し、`scripts/collect-run-facts.sh:189-192` の参照実装と一貫させる。

## Reproduction Steps

1. `/auto --batch` を、`/spec` で Size が降格または昇格する Issue を含めて実行する (例: Size M で `sub_start` された Issue が `/spec` の判定で XS へ降格し、patch route で着地する)。
2. バッチセッション完了後、生成された L3 `session.md` の `## Metrics` → `**Route mix**` 行を確認する (または `scripts/get-auto-session-report.sh <session-id> --metrics-only` を直接実行する)。
3. 報告された route 内訳が実際に実行された route と一致しないことを確認する。実測 (session `23043-1786197225`, 2026-08-09): 報告値 `patch: 1, pr: 2` に対し実態は `patch: 2, pr: 1`。#1256 は `sub_start` 時点で Size M として記録されたが `/spec` が XS へ降格し、`code-patch` phase で実行された。

## Root Cause

`scripts/get-auto-session-report.sh:170-179` の `ROUTE_MIX` jq は `.event == "sub_start"` のイベントのみを対象に、そのイベントの `.size` フィールドで patch (XS/S) / pr (M/L) / xl (XL) に振り分けている。`sub_start` は `run-auto-sub.sh` の最冒頭 (`scripts/run-auto-sub.sh:824-826`) で spec フェーズ実行前の Size を記録する。一方 `run-auto-sub.sh` は spec フェーズ完了後に Size を再取得し (`scripts/run-auto-sub.sh:852-858`、値が変化していれば `size_refresh` イベントを発火)、実際の code フェーズ (`code-pr` または `code-patch`) はこの **post-spec** の Size を根拠にディスパッチされる。したがって `ROUTE_MIX` は「spec 実行前の見込み」を集計しており、`/spec` が Size を変更した Issue では実行結果と乖離する。`scripts/collect-run-facts.sh:189-192` は同じ route を `code-pr` / `code-patch` phase イベントの有無から Issue 単位で正しく導出しており、これが本修正の参照実装となる。

## Changed Files

- `scripts/get-auto-session-report.sh`: `ROUTE_MIX` の jq (170-179 行目) を、Issue 単位で `code-pr` / `code-patch` phase イベントの有無から route を導出する形に書き換える (`collect-run-facts.sh` の Issue 単位 route 導出を踏襲)。`xl` は従来どおり `sub_start` の `size == "XL"` から導出し (変更なし)、`code-pr`/`code-patch` のいずれにも到達しなかった処理済み Issue は新設の `unknown` バケットに計上する。bash 3.2+ 互換 (jq ロジックのみの変更、新規 bash 構文なし)
- `tests/get-auto-session-report.bats`: post-spec で Size が降格したケース (`sub_start` の size と実行 route が食い違うフィクスチャ) を再現する `@test` を追加し、`Route mix` が実行された phase 側の route を報告することを検証する

## Implementation Steps

1. `scripts/get-auto-session-report.sh` の `ROUTE_MIX` 計算 (現行 170-179 行目) を書き換える: セッションイベントを `.issue` でグルーピングし、`sub_start` の `size == "XL"` を持つ Issue を `xl` として別扱いし、それ以外の処理済み Issue (`sub_start` または `phase_*` イベントを持つ Issue — 既存の `PROCESSED_ISSUES_JSON` と同じ判定条件) について、その Issue のイベント群に `phase == "code-pr"` が含まれれば `pr`、`phase == "code-patch"` が含まれれば `patch`、いずれも含まれなければ `unknown` と判定する。出力形式を `"patch: N, pr: N, xl: N, unknown: N"` とする (→ acceptance criteria 1, 2)
2. `tests/get-auto-session-report.bats` に新規 `@test` を追加する (after 1)。フィクスチャは session `23043-1786197225` の実例 (#1256/#1266/#1279) をモデルにする: `sub_start size=M` の直後に `phase_start`/`phase_complete phase=code-patch` を記録する Issue (post-spec M→XS 降格を模擬)、`sub_start size=S` で `code-patch` の Issue、`sub_start size=M` で `code-pr` の Issue を用意し、`Route mix` が `sub_start` の size ではなく実行された phase 側で `patch: 2, pr: 1` を報告することを検証する (→ acceptance criteria 4)
3. `bats tests/get-auto-session-report.bats` を実行し、既存 13 件 + 新規追加分がすべて PASS することを確認する (after 1, 2) (→ acceptance criteria 5)

Acceptance criteria 3 (`operate` route・`xl`・フェーズ未達 Issue の 3 点の採用理由記録) は実装ステップではなく本 Spec の「Notes」セクションの「Auto-Resolved Ambiguity Points」記載によって満たされる。

## Verification

### Pre-merge

- <!-- verify: rubric "get-auto-session-report.sh の ROUTE_MIX 導出が sub_start イベントの size フィールドではなく、実際に実行されたフェーズ (code-pr / code-patch) を根拠にしている" --> `scripts/get-auto-session-report.sh` の `Route mix` が、`sub_start` の `size` ではなく `code-pr` / `code-patch` phase イベントの有無から route を導出している
- <!-- verify: grep "code-patch" "scripts/get-auto-session-report.sh" --> `scripts/get-auto-session-report.sh` が `code-patch` を参照している
- <!-- verify: rubric "operate route の扱い (列を増やすか patch に含めるか)、xl の導出方式、code-* フェーズに到達しなかった Issue の計上方針の 3 点それぞれについて、採用した方式と理由が Spec に記載されている" --> `operate` route・`xl`・フェーズ未達 Issue の 3 点について、採用した扱いと理由が Spec に記録されている
- <!-- verify: grep "Route mix" "tests/get-auto-session-report.bats" --> bats テストが追加され、post-spec で Size が降格した Issue (`sub_start` の size と実行 route が食い違うフィクスチャ) で `Route mix` が実行 route 側を報告することを検証している
- <!-- verify: command "bats tests/get-auto-session-report.bats" --> `bats tests/get-auto-session-report.bats` 全件が PASS する (回帰保護 — 単独では常時 PASS のため上記の新規テスト追加 AC と組で機能する)

### Post-merge

- patch route と pr route が混在する `/auto --batch` の完走後、L3 retrospective の `Route mix` の内訳が実際の経路構成と一致することを観察する <!-- verify-type: observation event=auto-run session=next -->

## Notes

### Auto-Resolved Ambiguity Points (`/issue` からの引き継ぎ、non-interactive 自動解決)

1. **`operate` route の扱い**: 新規列を追加せず `patch` に含める。`code-patch` phase の有無のみで `patch` を判定する設計により、operate route の Issue も自動的に `patch` に含まれる — operate route は `run-code.sh --patch` を通じて同じ `code-patch` phase 名でディスパッチされ (`scripts/run-auto-sub.sh:888-889` で確認済み)、patch/operate の分岐は `run-code.sh` 内部で行われるため `run-auto-sub.sh` が emit する phase 名には現れない。`collect-run-facts.sh` が行っている個別のコメントマーカー探索 (`type=execution-log`/`type=execution-plan`) を複製すると、本 Issue のスコープ (route 導出元の切り替えのみ) を超えて実装量が増える。`Route mix` の出力は `session.md`/`/audit auto-session` にテキストとしてそのまま埋め込まれ、構造的にパースされないため、複製しないことによる後方互換上のリスクはない。
2. **`xl` の導出**: 現行どおり `sub_start` イベントの `size == "XL"` から導出する (変更なし)。XL 親 Issue は sub-issue へ分割されるため親 Issue 自身が `code-pr`/`code-patch` phase に到達することはなく (コードベース内に XL Issue スコープの `phase=="code-*"` イベントは存在しない)、phase イベントから `xl` を導出する手段が原理的に無い。本 Issue が修正する「post-spec Size 再評価の食い違い」というメカニズム自体が XL 自身の計上には適用されない。
3. **フェーズ未達の Issue**: 新設の `unknown` バケットに計上し、`patch`/`pr`/`xl` のいずれにも含めない。`collect-run-facts.sh:192` が同じ条件 (`code-pr`/`code-patch` のいずれの phase イベントも見つからない) で `"unknown"` を返す設計に倣い、2 スクリプト間の route 語彙を一貫させる。

### Steering Docs sync candidate cross-check

`get-auto-session-report.sh` を参照するファイルを `docs/`, `tests/`, `scripts/` から横断検索した結果、`tests/audit-auto-session.bats` が同スクリプトを対象とする別の bats ファイルとして見つかった。ただし同ファイルは `Route mix` / `ROUTE_MIX` を一切検証しておらず (`sub_start`/`size` を使うテストのみ)、実装前のベースライン実行 (`bats tests/audit-auto-session.bats` 7 件、`bats tests/get-auto-session-report.bats` 13 件、いずれも全件 PASS) でも本変更が影響する範囲ではないことを確認済み。`docs/structure.md` / `docs/tech.md` の同スクリプトへの言及は総称的な説明であり `Route mix` の内部フォーマットに依存していないため、更新不要。

### bats テスト入力フォーマット

新規 `@test` のフィクスチャは既存テストと同じ JSONL 形式 (`tests/get-auto-session-report.bats` の既存 `@test` を参照): 各行 `{"ts":"...","issue":N,"event":"...","session_id":"...",...}`。`sub_start` イベントは `size` フィールドを持ち、`phase_start`/`phase_complete` イベントは `phase` フィールド (`"code-patch"` または `"code-pr"`) を持つ。

### 文字列存在確認

実装前時点で `scripts/get-auto-session-report.sh` に `"code-patch"` 文字列は存在しない (grep で未検出、確認済み)。Implementation Step 1 の変更により新規に導入されるため、Pre-merge verify command 2 (`grep "code-patch" ...`) は実装後に PASS する。同様に `tests/get-auto-session-report.bats` に `"Route mix"` 文字列は現時点で存在せず、Implementation Step 2 で追加するアサーションにより Pre-merge verify command 4 が PASS する。

### jq ロジックの事前検証

`ROUTE_MIX` の新しい jq ロジックを、本 Issue の実測イベント (session `23043-1786197225`, #1256 M→patch 降格 / #1266 S→patch / #1279 M→pr / XL Issue 1 件 / phase 未到達 Issue 1 件) を模した合成フィクスチャで手動検証し、`patch: 2, pr: 1, xl: 1, unknown: 1` — 実測の実態 (`patch: 2, pr: 1`) と一致する結果を確認済み。

## Consumed Comments

- saito / MEMBER / first-class / `/issue` フェーズの Issue Retrospective — non-interactive 自動解決ログ (Auto-Resolve Log) の記録。内容は既に Issue 本文の「対応方針 (案)」「Auto-Resolved Ambiguity Points」に反映済みのため、本 Spec への追加指示なし / https://github.com/saitoco/wholework/issues/1289#issuecomment-5228135341
