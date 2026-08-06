# Issue #1083: issue: AC 監査に常時 UNCERTAIN になる verify command の検出基準を追加

## Consumed Comments

- saito / MEMBER / first-class / `/issue 1083 --non-interactive` の Issue Retrospective — AC1 (対象ファイル未確定) と AC4 (Pattern 2 拡張) の Auto-Resolved Ambiguity Points を記録 (内容は既に Issue 本文へ反映済みで、本 Spec の設計判断に新規の追加情報はない) / https://github.com/saitoco/wholework/issues/1083#issuecomment-5198831217

## Overview

`/issue` の AC verify command 監査は「常時 PASS になる verify command」(`skills/triage/skill-dev-verify-audit.md` Pattern 2) を検出できるが、「常時 UNCERTAIN になる verify command」(#1060 で実際に発生) を検出する基準を持たない。本 Issue はこの検出基準を追加し、あわせて `command` 型 verify command が対象スクリプトの exit code 設計に起因して常時 PASS になるケース (#1179/#1181/#1180 で実測) も PASS 側の監査基準に含める。

Issue 本文の AC1 は対象ファイルの選定を `/spec` に委ねている (`skills/issue/SKILL.md` の自己完結型監査セクション、または `skills/triage/skill-dev-verify-audit.md` の Pattern 表拡張のいずれか)。コードベース調査の結果、`skills/triage/skill-dev-verify-audit.md` (Pattern 2 の常時 PASS 検出が実際に定義されている場所) を採用する。判断根拠は Notes を参照。

## Changed Files

- `skills/triage/skill-dev-verify-audit.md`: 「### Pattern 6: 常時 UNCERTAIN な verify command」を新設 (5 サブパターン + `command` 型 AC の Pre-merge 配置判定基準を含む)。「### Pattern 2: 常時 PASS な verify command」に exit code 設計起因の常時 PASS 検出を追記

## Implementation Steps

1. `skills/triage/skill-dev-verify-audit.md` の Pattern 5 (`### Pattern 5: Destructive Command Safety Check`) の直後、`## Non-Destructive Audit Behavior` の直前に「### Pattern 6: 常時 UNCERTAIN な verify command (Always-UNCERTAIN Command)」を新設する。既存 Pattern と同じ構成 (Detect / 具体例 / Fix) で、Issue 本文の「UNCERTAIN 側の典型パターン」表にある 5 サブパターンを列挙する: (1) `section_contains`/`section_not_contains` の heading 引数に先頭の `#` を含める、(2) 存在しないファイルパスを参照、(3) 引数個数不足、(4) 未定義のコマンド名、(5) 対応 CI job のない safe mode 限定コマンド (`command` 等) を Pre-merge に置く。(5) の Fix として、`command` 型 AC を Pre-merge に置いてよい判定基準 ((a) 対応する CI job が存在し `/review` の CI reference fallback が解決できる、(b) スクリプトが失敗時に非ゼロを返す設計である — いずれも満たさない場合は Post-merge へ移すか `verify-type: manual` にする) を明記する (→ acceptance criteria AC1, AC2, AC3)
2. 同ファイルの「### Pattern 2: 常時 PASS な verify command」に、`command` 型 AC が対象スクリプトの exit code 設計 (例: `check-translation-sync.sh` は `--fail-if-outdated` フラグなしでは常に exit 0 を返す informational スクリプト) に起因して常時 PASS になるケースの Detection approach と Fix を追記する (→ acceptance criteria AC4, AC5)
3. `bats tests/issue.bats` を実行し、既存テストに regression がないことを確認する — 同ファイルは pre-merge-preview tier 機能の content-assertion テストのみで本 Issue の変更対象と重複しないため、無変更で PASS する想定 (→ acceptance criteria AC6)

## Verification

### Pre-merge

- <!-- verify: rubric "AC verify command 監査 (skills/issue/SKILL.md 内の自己完結型監査セクション、または skills/triage/skill-dev-verify-audit.md の Pattern 表拡張のいずれか、対象ファイルの選定は /spec が判断する) に、常時 UNCERTAIN になる verify command を検出する基準が追加されている。少なくとも section_contains / section_not_contains の heading 引数に先頭の # を含めるパターンが明示的に列挙されている" --> UNCERTAIN 側の検出基準が追加されている (対象ファイルは /spec が判断)
- <!-- verify: rubric "追加された検出基準が、既存の『常時 PASS になる verify command』の監査基準と並列に (どちらも監査対象であることが分かる形で) 記述されている" --> PASS 側・UNCERTAIN 側が並列に記述されている
- <!-- verify: rubric "command 型 verify command を Pre-merge AC に置く際の判定基準 (対応 CI job が存在するか、スクリプトが失敗時に非ゼロを返すか) が記述され、どちらも満たさない場合の代替 (post-merge へ移す / verify-type: manual にする) が示されている" --> `command` 型 AC の Pre-merge 配置基準が記述されている
- <!-- verify: rubric "skills/triage/skill-dev-verify-audit.md の Pattern 2 (常時 PASS な verify command) が、スクリプトの exit code 設計に起因する常時 PASS (例: --fail-if-outdated なしで常に exit 0 を返す check-translation-sync.sh) も検出対象に含む形に拡張されている" --> Pattern 2 が exit code 設計に起因する常時 PASS を検出対象に含む
- <!-- verify: section_contains "skills/triage/skill-dev-verify-audit.md" "### Pattern 2" "exit code" --> Pattern 2 セクション内に exit code 関連の記述がある
- <!-- verify: command "bats tests/issue.bats" --> `tests/issue.bats` が PASS する

### Post-merge

- `section_contains` の heading 引数に `###` を含む AC を持つ Issue を `/issue` に通し、監査が指摘して修正されることを確認する (verify-type: manual)

## Notes

### AC1 対象ファイルの判断根拠

Issue 本文の Auto-Resolved Ambiguity Points は、`/issue` の自己完結型監査 (BRE メタ文字検出セクション、`skills/issue/SKILL.md` Step 4) と `/triage` の Pattern 表 (`skill-dev-verify-audit.md`) の両方に置き場所としての妥当性があるとし、最終判断を `/spec` に委ねていた。以下の理由で `skill-dev-verify-audit.md` (Pattern 6 として追加) を採用する。

1. **AC2 の「並列」要件との整合性**: 既存の「常時 PASS」検出基準 (Pattern 2) は `skill-dev-verify-audit.md` にのみ存在し、`skills/issue/SKILL.md` には存在しない (grep で確認済み)。UNCERTAIN 側を同ファイルに Pattern 6 として追加すれば、Pattern 2/6 が単一ドキュメント内で「どちらも監査対象である」ことが構造的に明示される。`issue/SKILL.md` 側に追加した場合、Pattern 2 とは別スキルの別ファイルになり「並列」性が弱まる。
2. **AC4 との一貫性**: AC4 は Pattern 2 の拡張を要求しており、対象ファイルは `skill-dev-verify-audit.md` に一意に決まる (Issue 本文の Auto-Resolved Ambiguity Points 2 番目の項目より、こちらは曖昧性なし)。UNCERTAIN 側も同ファイルに置くことで、PASS/FAIL/UNCERTAIN の 3 側面が単一ファイルの Pattern 一覧に集約される。
3. **既存 Pattern 構造の再利用**: Pattern 1–5 は「Detect / 具体例 / Fix」という統一フォーマットを持ち、UNCERTAIN 側の 5 サブパターンもこの形式にそのまま収まる。`/triage` の Processing Steps ("For each extracted verify command, check against the patterns below") が自動的に Pattern 6 も対象にするため、呼び出し側 (`skills/triage/SKILL.md` Step 7, Bulk Execution Step 3 substep 7) の変更は不要。

### コードベース調査で判明した構造的非対称性 (スコープ外の観察)

`skills/issue/SKILL.md` には 2 つのフローがあり、triage 監査 (Pattern 表) と AC 分類の実行順序が逆転している:
- **New Issue Creation**: Step 4 (AC 分類・verify command 割当) → Step 8 (triage auto-chain、`triaged` ラベル不在時のみ) — Step 8 の監査は Step 4 の最終 AC を見るため機能する
- **Existing Issue Refinement** (#1083 自身もこのフロー): Step 2 (triage auto-chain、`triaged` ラベル不在時のみ) → Step 7 (AC 分類・verify command 割当) — 監査が AC 分類より **先に** 走るため、Step 7 で新規 authoring された verify command は同一セッション内では Pattern 表監査の対象にならない
- 既に `triaged` ラベルが付与済みの Issue (今回の #1083 自身を含む) では Step 2 の auto-chain 自体がスキップされるため、Pattern 表監査は一切実行されない

この非対称性は Pattern 1–5 (既存) にも同様に存在する既存の構造的特性であり、#1060 の実例 (Existing Issue Refinement で新規 authoring された `section_contains` AC が監査をすり抜けた) を部分的に説明する。ただし本 Issue の Purpose は「検出基準の追加」であり、監査の実行タイミング自体の是正 (triage 実行順序の変更) はスコープ外と判断した。将来的に Issue 化する価値はあるが、既存 Pattern 1–5 にも共通する既存動作の変更であり Size S の本 Issue 単独では扱わない。

### Pattern 番号の付番方針

新規 Pattern は既存 Pattern 1–5 を維持したまま末尾に **Pattern 6** として追加する (Pattern 4/5 のリナンバーはしない)。理由: 過去の複数 Spec (`docs/spec/issue-1061-honor-always-pr-in-route.md` 等) が "Pattern 4" を patch route チェックとして番号で参照しており、リナンバーは無用な参照ズレを生む。

## Code Retrospective

### Deviations from Design

N/A — Implementation Steps 1–3 の通りに実装した。

### Design Gaps/Ambiguities

N/A — Spec の Notes で AC1/AC4 の対象ファイル選定根拠が既に明記されており、実装時に新たな曖昧性は発生しなかった。

### Rework

N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Pattern 6 は既存 Pattern 1–5 を維持したまま末尾に追加し、Pattern 4/5 の番号は変更しなかった (Spec Notes の付番方針に従う)
- Pattern 2 は新規 Pattern を起こさず、既存セクションに exit code 起因の常時 PASS 検出を追記する形で拡張した (AC4 が「Pattern 2 の拡張」を要求しているため)

### Deferred Items
- Existing Issue Refinement フローにおける triage 監査と AC 分類の実行順序の非対称性 (Spec Notes 記載) は本 Issue のスコープ外のまま
- Post-merge AC (`###` heading を持つ AC を `/issue` に通し、監査が指摘・修正されることを確認) は未実行 — merge 後に `/verify` で対応

### Notes for Next Phase
- `/review` では、Pattern 6 サブパターン 5 (`command` 型 AC の Pre-merge 配置判定基準) の記述が Issue 本文の「実測による補正」節 (#1179/#1181/#1180) の結論と整合しているかを確認する
- `/verify` の post-merge AC は、実際に `###` heading を含む AC を持つ Issue を `/issue` に通して Pattern 6 サブパターン 1 が検出されることを確認する必要がある (manual verify-type)
