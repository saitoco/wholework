# Issue #1283: doc: 翻訳出力の frontmatter 残存で SSoT マッピングが二重主張になる状態を解消

## Overview

`docs/ja/visual-reproduction.md` は `/doc translate` による翻訳出力であるにもかかわらず `type: project` + `ssot_for: visual-reproduction-methodology` の frontmatter を保持しており、`skills/doc/translate-phase.md:53` の「翻訳出力からフロントマターを除去する」規定に違反している。`skills/doc/SKILL.md` の「Document Traversal (common procedure)」はこのファイルを除外しないため、`visual-reproduction-methodology` の SSoT が `docs/visual-reproduction.md` と二重主張される状態になっており、`/doc` の drift/重複判定や `/audit` の Project Documents 収集が曖昧になる。Issue 本文は当該ファイルの frontmatter 除去に加え、再発防止策の要否・実装箇所 (Document Traversal 側 or translate 側) の判断を `/spec` に委ねている。

## Reproduction Steps

1. `docs/ja/*.md` (10 ファイル) の各ファイル先頭行が `---` かどうかを確認する: `awk 'FNR==1 && /^---$/ {print FILENAME}' docs/ja/*.md` → `docs/ja/visual-reproduction.md` のみ該当し、他 9 ファイルは該当しない
2. 該当ファイルの内容を確認する: `head -6 docs/ja/visual-reproduction.md` → `---` / `type: project` / `ssot_for:` / `  - visual-reproduction-methodology` / `---` (1-5 行目) が残存している
3. `skills/doc/translate-phase.md:53` の規定 ("Remove the source file's frontmatter ... output pure Markdown without frontmatter") と照合すると、この状態は規定違反である

## Root Cause

- **混入経路**: `docs/ja/visual-reproduction.md` は `/doc translate ja` の実行結果ではなく、英語版 `docs/visual-reproduction.md` と同一コミット (PR #451, closes #439, 2026-05-11) で直接追加されたファイルである (`git log --follow -- docs/ja/visual-reproduction.md` の変更コミットが1件のみであることを確認済み)。英語版の frontmatter がそのままコピーされ、翻訳出力の除去規定を経由しなかった。
- **検知されなかった理由 (設計上の背景)**: `/doc translate` の元設計 (Issue #58, `docs/spec/issue-58-doc-translate.md`) は「frontmatter を持たない」という不変条件のみに依存して `skills/doc/SKILL.md` の「Document Traversal (common procedure)」から翻訳ファイルを自然除外する方式を採用しており、`docs/{lang}/` に対する明示的なパス除外を持たない。同 Spec 自身の `## spec retrospective`（Minor observations）は、この「frontmatter 非保持による自然除外」と「`sync --deep` 側の `.md` 統合スキャンにおける明示除外」という二段構えの挙動が将来の読み手に分かりにくい可能性を、実装当時から既に指摘していた。
- **影響範囲 (追加調査で判明)**: `type: project` frontmatter を Grep で収集する処理は `skills/doc/SKILL.md` の Document Traversal 以外にも存在する。`skills/audit/SKILL.md` の drift サブコマンド (Load Project Documents, 63-67 行目) と fragility サブコマンド (同名セクション, 674-678 行目) が、それぞれ独立に同じ4項目の除外パターンを重複定義している (共通モジュール参照ではなく直接コピー)。そのため Issue 本文が指摘する「`/audit` の Project Documents 収集にも翻訳ファイルが混入する」実害を止めるには、`skills/doc/SKILL.md` 側の修正だけでは不十分で、この2箇所にも同じ除外を適用する必要がある。なお `modules/doc-checker.md` (52-53 行目) は別目的の走査だが、既に `docs/{lang}/` / `README.{lang}.md` の除外を実装済みであり、追加する文言の参考にした。

## Changed Files

- `docs/ja/visual-reproduction.md`: frontmatter ブロック (1-6 行目、`---` ... `---` と後続の空行) を削除し、言語切り替え banner (`[English](../visual-reproduction.md) | 日本語`) から始まる形に揃える
- `skills/doc/SKILL.md`: 「Document Traversal (common procedure)」§ Step 2 の除外パターン一覧 (既存4項目) に、翻訳出力 (`docs/{lang}/`, `README.{lang}.md`) の除外を追加する
- `skills/audit/SKILL.md`: drift サブコマンド・fragility サブコマンドそれぞれの「Load Project Documents」§ Step 2 除外パターン一覧 (2箇所、既存4項目ずつ) に、同じ翻訳出力の除外を追加する

## Implementation Steps

1. `docs/ja/visual-reproduction.md` の frontmatter ブロック (`---` ... `---` および直後の空行。現状 1-6 行目) を削除し、`docs/ja/` 配下の他 9 ファイルと同じくファイル先頭行を言語切り替え banner (`[English](../visual-reproduction.md) | 日本語`) にする (→ acceptance criteria AC1, AC2)
2. `skills/doc/SKILL.md` の「Document Traversal (common procedure)」セクション、Step 2 の除外パターン一覧に、既存の `Paths starting with .tmp/ (temporary files)` 項目に続けて「翻訳出力: `docs/{lang}/` 配下のパス、およびプロジェクトルートの `README.{lang}.md` (`/doc translate {lang}` が生成)」を追加する。文言は同ファイル内「sync Bidirectional Normalization」§ Step 2 (Scan scope) の既存の「Translation output」除外記述と `modules/doc-checker.md` の除外記述を参考に揃える (→ acceptance criteria AC2, AC3)
3. `skills/audit/SKILL.md` の drift サブコマンド (「Load Project Documents」内、`Paths starting with .tmp/` 項目を含む除外リスト。現状 63-67 行目) と fragility サブコマンド (同名セクション。現状 674-678 行目) それぞれの除外パターン一覧に、Step 2 と同内容の翻訳出力除外を追加する (2箇所とも同じ変更) (→ acceptance criteria AC3)
4. 採用案 (B: frontmatter 除去 + Document Traversal 側3箇所への構造的除外追加) と、不採用とした代替案の判断根拠を本 Spec の「Notes」節に記録する (→ acceptance criteria AC3)

## Verification

### Pre-merge

- <!-- verify: rubric "docs/ja/visual-reproduction.md が frontmatter を持たず、docs/ja/ 配下の他ファイルと同じく言語切り替え banner から始まっている" --> 当該ファイルの frontmatter が除去されている
- <!-- verify: command "test $(awk 'FNR==1 && /^---$/ {c++} END {print c+0}' docs/ja/*.md) -eq 0" --> `docs/ja/` 配下の各ファイル先頭行に frontmatter (`---`) を持つものが 1 件も残っていない
- <!-- verify: rubric "採用案 (A または B) と不採用理由が Spec に記録されている。案 B を採る場合、再発防止を Document Traversal 側と translate 側のどちらに入れたか、その判断根拠も記録されていること" --> 案の採否と実装箇所の判断が記録されている

### Post-merge

- 次回 `/doc sync --deep` 実行時に、`visual-reproduction-methodology` の SSoT が `docs/visual-reproduction.md` 単独に解決されることを観察する <!-- verify-type: observation event=auto-run session=next -->

## Notes

### 案の採否

**採用: 案 B (frontmatter 除去 + 再発防止)**

- **案 A (frontmatter 除去のみ) を不採用とした理由**: 実害の直接原因は `/doc translate` の実行不備ではなく、英語版と同一コミットでの直接編集によるフロントマター混入だった (Root Cause 参照)。案 A のみでは、同種の直接編集や将来の `/doc translate` 不備が再発した場合に検知できず、Issue #58 の spec retrospective が既に指摘していた「暗黙の不変条件 (frontmatter 非保持) への依存」というリスクがそのまま残る。

- **再発防止の実装箇所: Document Traversal 側 (translate 側の後処理ではなく)**: 今回の実害は `/doc translate` を経由しない直接編集が原因であり、`translate-phase.md` 側に出力後チェックを追加しても、このケースはそもそも `/doc translate` を通過していないため検知できなかった。一方 Document Traversal 側にパスベースの明示除外を追加すれば、混入経路によらず (`/doc translate` の不備・直接編集・将来の他 skill による書き込みのいずれであっても) `docs/{lang}/` 配下への frontmatter 混入を構造的に無害化できる。`modules/doc-checker.md` (52-53 行目) には既に同種の除外が実装済みで、`skills/doc/SKILL.md` 341 行目付近 (`sync --deep` の `.md` 統合スキャン) にも同種の除外が既存であり、Document Traversal 側への追加はこれらと文言・方針を揃える自然な選択となる。

- **実装箇所が Document Traversal (common procedure) の1箇所ではなく3箇所になった理由**: `type: project` を Grep で収集する処理は `skills/doc/SKILL.md` の共有手順に加え、`skills/audit/SKILL.md` の drift・fragility 両サブコマンドにも同一の4項目除外リストが独立コピーされている (共通モジュール参照ではなく直接複製、`grep -rn "Paths starting with \`\$SPEC_PATH/\`\|Paths containing \`node_modules/\`" skills/ modules/` で該当3箇所を確認済み)。Issue 本文が指摘する「`/audit` の Project Documents 収集にも翻訳ファイルが混入する」実害を実際に止めるには、この2箇所にも同じ除外を適用する必要があるため、Changed Files / Implementation Steps に含めた。

- **スコープ外としたもの**:
  - `translate-phase.md` 側への出力後チェック追加: Document Traversal 側の除外と機能的に重複し、かつ今回の実害 (直接編集起因) を直接防止できないため見送った。将来 `/doc translate` 実行そのものの不備 (Step 3 のフロントマター除去指示の見落とし) が観測された場合は、改めて検討する。
  - `skills/audit/SKILL.md` の2箇所の重複定義を `skills/doc/SKILL.md` への参照に統合するリファクタリング: 今回のバグ修正とは独立した設計変更であり、本 Issue のスコープを超えるため実施しない (観察事項として記録するのみ)。

## Consumed Comments
- saito / MEMBER / first-class / Issue Retrospective — AC2 の verify command を awk ベースの frontmatter 判定に修正済み (environment-adaptation.md 内の fenced code block 由来の誤検出を回避)。Post-merge observation AC に `session=next` 追加済み。追加で解決すべき曖昧性なし / https://github.com/saitoco/wholework/issues/1283#issuecomment-5226925420

## Code Retrospective

### Deviations from Design
- N/A (Implementation Steps 1-4 を Spec 記載どおりに実施。案の採否は既に Spec Notes に記録済みのため追加記録なし)

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Implemented exactly per Spec Implementation Steps 1-3 (frontmatter removal + 3-location Document Traversal exclusion addition); no deviation from the adopted 案 B recorded in Notes
- Step 4 (recording the adoption decision) was already satisfied by the Spec's existing `## Notes` § 案の採否, written during the spec phase — no additional recording needed in code phase

### Deferred Items
- Post-merge observation AC (`session=next`): confirm on next `/doc sync --deep` run that `visual-reproduction-methodology` SSoT resolves singularly to `docs/visual-reproduction.md`
- Scope-out items already recorded in Spec Notes § スコープ外としたもの (translate-phase.md output-check, audit/SKILL.md duplication refactor) — not re-litigated here

### Notes for Next Phase
- All 3 pre-merge AC verified PASS locally (rubric AC1/AC3 self-judged adversarially against file content and Spec Notes; AC2 command executed directly) — Issue checkboxes already updated to `[x]`
- Full bats suite (`bats --jobs 18 tests/`) passed; 2 initial failures in `tests/post_merge_check.bats` were confirmed parallel-only flakiness (per docs/tech.md's documented pattern) and cleared on serial re-run

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- 起票時に付けた AC2 の verify command (`grep -rl '^type: ' docs/ja/`) が欠陥を持っていた。`docs/ja/environment-adaptation.md` の fenced code block 内サンプル (`type: domain`) を frontmatter と誤検出するため、frontmatter 除去後も恒久 FAIL になる状態だった。triage フェーズがこれを実測で再現し、先頭行のみを判定する `awk 'FNR==1 && /^---$/'` ベースに置き換えている
- 起票時の「実装前に FAIL することを確認した」という検証は、`modules/verify-patterns.md` §9 が戒める「常時 PASS」側は塞いだが「常時 FAIL」側は塞げていなかった。pre-fix FAIL の確認だけでは不十分で、**修正を模した状態で PASS するかの確認**が対になって初めて §9 の趣旨を満たす

#### spec
- Issue 本文の想定 (対象 1 ファイル + 再発防止 1 箇所) に対し、調査で対象が 3 箇所に拡大した。Issue 本文が挙げた実害「`/audit` の Project Documents 収集にも翻訳ファイルが混入する」を実際に止めるには `skills/doc/SKILL.md` だけでは不十分という判断は正しい
- 案 A/B の採否判断を Issue 本文が明示的に `/spec` へ委譲していたため、Spec Notes に採用理由・不採用理由・実装箇所の判断根拠が揃って記録された。委譲先を Issue 本文で名指ししたことが機能している

#### code
- Implementation Steps 1-4 を逸脱なく実施。rework なし、fixup/amend なし
- ローカル全スイートで `tests/post_merge_check.bats` の並列限定 flake を 2 件踏み、直列再実行で解消。#1282 が `docs/tech.md` に文書化したパターンがそのまま再現・適用された初の実例

#### review
- patch route のため `/review` フェーズなし

#### merge
- patch route のため `/merge` フェーズなし。main 直コミット (7c85d8bf)、コンフリクトなし

#### verify
- pre-merge 3 件はすべて code フェーズで検証済みのため SKIPPED。observation 1 件は `auto-run` 未発火のため SKIPPED
- FAIL / UNCERTAIN ゼロ

### Improvement Proposals

- **`type: project` 収集の除外パターンが 3 箇所に重複定義されている** — `skills/doc/SKILL.md` の Document Traversal (common procedure)、`skills/audit/SKILL.md` の drift サブコマンド、同 fragility サブコマンドが、共通モジュール参照ではなく同一の除外リストを独立コピーで持つ。本 Issue は 1 項目の追加のために 3 箇所を同時編集する必要があり、次に除外項目が増えたときも同じコストと同期漏れリスクが発生する。共通モジュール (`modules/` 配下) への切り出しと 3 箇所からの参照化を検討する。Spec Notes § スコープ外としたもの に観察事項として記録済み
