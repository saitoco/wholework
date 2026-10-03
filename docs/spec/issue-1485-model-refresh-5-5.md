# Issue #1485: models: 古いモデル ID の固定を無くし、モデルの記述を Opus 5.5 / Sonnet 5.5 / Fable 5.1 に合わせる

## Consumed Comments

- 該当なし (cutoff: 2026-10-02T23:37:09Z = 直近の `phase/*` ラベル付与時刻。cutoff 以降のコメント 0 件、cross-phase marker コメントも 0 件)

## Overview

Opus 5.5 (2026-09-22) / Sonnet 5.5 (2026-09-28) / Fable 5.1 (2026-09-01) のリリースに合わせて、Wholework のモデル指定と記述を現行モデルに揃える。

- **実行に効く固定指定を無くす**: `scripts/spawn-recovery-subagent.sh` の `ANTHROPIC_MODEL="claude-sonnet-4-6"` を他の `run-*.sh` と同じ `sonnet` エイリアスに揃える。`scripts/run-spec.sh --fable` の `claude-fable-5` を `claude-fable-5-1` に更新し、モデル比較とコスト警告の文言も合わせる
- **テストで変更を検出できるようにする**: `tests/run-spec.bats` の `--fable` テストを完全一致 (`grep -qx`) にし、古い ID では FAIL する形にする。`tests/spawn-recovery-subagent.bats` にエイリアス指定を確認するテストを追加する
- **古い表記を直す**: `docs/tech.md` (と `docs/ja/tech.md`) のモデル・エイリアス・effort の記述、`skills/spec/SKILL.md` の `--opus` / `--fable` 説明、画像解像度の記述 (`modules/*-adapter.md`)、`agents/review-bug.md` の「Opus 5 に解決される」、`SECURITY.md` の auto mode 対応モデル
- **commit trailer をモデル名なしの形に統一する**: 20 箇所 (12 ファイル) の `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>` を `Co-Authored-By: Claude <noreply@anthropic.com>` に置き換える

## Changed Files

**実行に効く固定指定:**

- `scripts/spawn-recovery-subagent.sh`: `ANTHROPIC_MODEL="claude-sonnet-4-6"` → `ANTHROPIC_MODEL=sonnet` (他の `run-*.sh` と同じ形)。文字列の置き換えのみ — bash 3.2+ 互換
- `tests/spawn-recovery-subagent.bats`: `claude -p` が `ANTHROPIC_MODEL=sonnet` と `--model sonnet` で呼ばれることを完全一致で確認する新規テストを追加
- `scripts/run-spec.sh`: `--fable` のモデル ID を `FABLE_MODEL_ID="claude-fable-5-1"` 定数に切り出し、`MODEL` への代入と比較 (`if [[ "$MODEL" == ... ]]`) の両方で使う。コスト警告を Fable 5.1 の現行値に更新。ファイル内の commit trailer (1 箇所) も置き換え — bash 3.2+ 互換
- `tests/run-spec.bats`: `@test "success: --fable switches model to claude-fable-5"` を `claude-fable-5-1` の完全一致 (`grep -qx`) 確認に変更 (テスト名も更新)

**commit trailer (モデル名なしの形に統一、計 20 箇所):**

- `skills/auto/SKILL.md`: trailer 4 箇所
- `skills/code/SKILL.md`: trailer 4 箇所 (コメント行 `# Co-Authored-By: ...` 1 箇所を含む)
- `skills/review/SKILL.md`: trailer 2 箇所
- `skills/merge/SKILL.md`: trailer 1 箇所
- `skills/verify/SKILL.md`: trailer 1 箇所 + `<!-- skill-body-sha: H -->` マーカーの再計算 (行数は変わらないので `<!-- skill-body-lines: 997 -->` は据え置き)
- `skills/doc/translate-phase.md`: trailer 1 箇所
- `modules/doc-commit-push.md`: trailer 1 箇所
- `scripts/run-code.sh`: trailer 1 箇所 — 文字列リテラルの置き換えのみ、bash 3.2+ 互換
- `scripts/run-auto-sub.sh`: trailer 2 箇所 — 文字列リテラルの置き換えのみ、bash 3.2+ 互換
- `scripts/append-consumed-comments-section.sh`: trailer 1 箇所 — 文字列リテラルの置き換えのみ、bash 3.2+ 互換
- `agents/orchestration-recovery.md`: recovery plan の例にある trailer 1 箇所
- (`scripts/run-spec.sh` の 1 箇所は上に記載)

**古い表記:**

- `skills/spec/SKILL.md`: `--opus` / `--fable` / `--max` の説明を現行モデルに合わせる (`Opus 4.x` / `Fable 5` の表記を除く)
- `docs/tech.md`: Phase-specific model and effort matrix 周辺 — 既定の親を Sonnet 5.5 に、エイリアスの解決先 (`sonnet` / `opus` / `fable`) の追記、`run-spec.sh` 行の Fable 5.1 化、5.5 / 5.1 世代の effort の推奨値と Wholework の判断の追記、Fable 注記の 5.1 化、Alias pin policy の更新、commit trailer の方針の追記
- `docs/ja/tech.md`: `docs/tech.md` の変更を日本語で反映 (`docs/translation-workflow.md` の同期手順に従う)
- `modules/browser-adapter.md`: 「Claude Opus 4.7」基準の画像解像度の記述を「Claude 4.7 以降のモデル」に一般化 (値 2576 px / 4,784 tokens は据え置き)。座標の記述も合わせる
- `modules/lighthouse-adapter.md`: 同上
- `modules/visual-diff-adapter.md`: 同上
- `agents/review-bug.md`: cyber classifier の注記にある「currently resolves to Opus 5」と Fable 5 のフォールバック先の記述を現行に合わせる
- `SECURITY.md`: auto mode 対応モデルの「or Fable 5」を「or a Fable model」に変更

**Steering Docs sync candidate (`/code` が最終判断):**

- [Steering Docs sync candidate] keyword `claude-fable-5`: `docs/` `tests/` `scripts/` `modules/` の 26 ファイルに一致するが、`docs/spec/` `docs/reports/` `docs/ja/reports/` (過去の記録) を除くと `docs/tech.md` / `docs/ja/tech.md` / `scripts/run-spec.sh` / `tests/run-spec.bats` の 4 ファイルで、すべて上に記載済み
- [Steering Docs sync candidate] keyword `Co-Authored-By: Claude Sonnet 5`: 8 ファイルに一致。うち `docs/spec/` の 3 ファイル (過去の記録) を除く 5 ファイルは上に記載済み
- [Steering Docs sync candidate] keyword `Opus 4.x`: 5 ファイルに一致。`docs/tech.md` / `docs/ja/tech.md` の「Opus 4.x」は「Opus 5 watch items」注記の rate limit pool の説明 (Opus 5 と Opus 4.x の比較) で、古い表記ではないため変更不要。残りは `docs/spec/` `docs/reports/` (過去の記録)
- [Steering Docs sync candidate] keyword `doc-commit-push.md`: 7 ファイルに一致。`docs/structure.md` / `docs/ja/structure.md` はモジュールの説明のみで trailer に触れていないため変更不要。残りは `docs/spec/`
- [Steering Docs sync candidate] keyword `claude-sonnet-4-6`: 10 ファイルに一致。`scripts/spawn-recovery-subagent.sh` 以外は `docs/spec/` `docs/reports/` (Exclusions 参照)
- [Steering Docs sync candidate] keyword `spawn-recovery-subagent.sh` skipped: matched 65 files (no discriminating power)
- [Steering Docs sync candidate] keyword `run-spec.sh` skipped: matched 150 files (no discriminating power)
- [Steering Docs sync candidate] keyword `append-consumed-comments-section.sh` skipped: matched 45 files (no discriminating power)
- [Steering Docs sync candidate] keyword `browser-adapter.md` skipped: matched 32 files (no discriminating power)
- [Steering Docs sync candidate] keyword `lighthouse-adapter.md` skipped: matched 17 files (no discriminating power)
- [Steering Docs sync candidate] keyword `visual-diff-adapter.md` skipped: matched 16 files (no discriminating power)
- [Steering Docs sync candidate] keyword `Opus 4.7` skipped: matched 41 files (no discriminating power)。`docs/` 配下の該当は過去の記録 (`docs/reports/` `docs/spec/`) か tokenizer の導入時期の説明で、画像解像度の記述は上の 3 つの adapter のみ

## Implementation Steps

1. `scripts/spawn-recovery-subagent.sh` の `claude -p` 呼び出しブロック (`# --- Invoke claude -p (following run-*.sh precedent) ---` の直後) で、`ANTHROPIC_MODEL="claude-sonnet-4-6" \` を `ANTHROPIC_MODEL=sonnet \` に変える。`--model sonnet` / `--effort medium` はそのまま残す (両方を指定するのは `-p` モードの不具合 anthropics/claude-code#22362 への対策で、他の `run-*.sh` と同じ)。`tests/spawn-recovery-subagent.bats` に新規テスト `@test "spawn-recovery: claude -p is invoked with the sonnet alias (no pinned model ID)"` を追加する: テスト内で `export CLAUDE_ENV_LOG="$BATS_TEST_TMPDIR/claude-env.log"` し、`$MOCK_DIR/claude-mock` を「`echo "ANTHROPIC_MODEL=${ANTHROPIC_MODEL:-}" >> "$CLAUDE_ENV_LOG"`、`--model` の次の引数を `MODEL_VALUE=<値>` として同じログに追記、最後に `{"action":"retry","rationale":"transient failure","steps":[]}` を echo する」スクリプトに上書きし、`cd "$BATS_TEST_TMPDIR"` してから `run bash "$SCRIPT" code 42 --log "$LOG_FILE"` を実行、`[ "$status" -eq 0 ]`、`grep -qx "ANTHROPIC_MODEL=sonnet" "$CLAUDE_ENV_LOG"`、`grep -qx "MODEL_VALUE=sonnet" "$CLAUDE_ENV_LOG"` で確認する (→ acceptance criteria 1)
2. `scripts/run-spec.sh` を更新する (parallel with 1) (→ acceptance criteria 2):
   - `# Parse options` ブロックの直前に、Fable を `fable` エイリアスではなく ID で固定する理由 (コストに敏感な opt-in であること、`fable` エイリアスは Claude apps gateway のセッションでは Fable 5 に解決されること、新しい Fable が出たら下のコスト警告と合わせて更新すること、`docs/tech.md` 参照) を英語コメントで書き、`FABLE_MODEL_ID="claude-fable-5-1"` を定義する
   - `--fable)` の `MODEL="claude-fable-5"` を `MODEL="$FABLE_MODEL_ID"` に変える
   - 警告ブロックの `if [[ "$MODEL" == "claude-fable-5" ]]; then` を `if [[ "$MODEL" == "$FABLE_MODEL_ID" ]]; then` に変え、警告文を次の 4 行にする (既存テストが見る `credit` / `retention` の語を残す): `WARNING: Fable 5.1 opt-in — cost \$10/\$50 per MTok (2.5x Opus 5.5, 5x Sonnet 5.5)` / `WARNING: Usage credits may be required (subscription plans, depending on plan/seat tier)` / `WARNING: 30-day retention required — ZDR organizations not supported` / `WARNING: Requires Claude Code v2.1.257 or later`
   - 同ファイルの trailer 1 箇所は Step 4 で置き換える
3. `tests/run-spec.bats` の `@test "success: --fable switches model to claude-fable-5"` を `@test "success: --fable switches model to claude-fable-5-1"` に改名し、`grep -q "MODEL_VALUE=claude-fable-5"` / `grep -q "ANTHROPIC_MODEL=claude-fable-5"` を `grep -qx "MODEL_VALUE=claude-fable-5-1" "$CLAUDE_CALL_LOG"` / `grep -qx "ANTHROPIC_MODEL=claude-fable-5-1" "$CLAUDE_CALL_LOG"` に変える。mock の `claude` はログに `MODEL_VALUE=<--model の次の引数>` と `ANTHROPIC_MODEL=<環境変数>` を 1 行ずつ書くので、`-x` (行全体の一致) にすれば `claude-fable-5` のような古い ID では FAIL する (after 2) (→ acceptance criteria 3)
4. commit trailer 20 箇所を `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>` → `Co-Authored-By: Claude <noreply@anthropic.com>` に置き換える (parallel with 1, 2)。対象は Changed Files の「commit trailer」に挙げた 12 ファイル (例: `sed -i 's/Co-Authored-By: Claude Sonnet 5 </Co-Authored-By: Claude </' <file>`)。置き換え後、`grep -rnE "Co-Authored-By: Claude [^<]" skills/ scripts/ modules/ agents/` が 0 件であることを確認する。`skills/verify/SKILL.md` は `grep -v '<!-- skill-body-' skills/verify/SKILL.md | shasum -a 256 | cut -c1-8` で hash を再計算して `<!-- skill-body-sha: H -->` を更新し、`bash scripts/check-skill-body-hash.sh` が exit 0 になることを確認する (`<!-- skill-body-lines: 997 -->` は行数が変わらないので据え置き) (→ acceptance criteria 5)
5. `skills/spec/SKILL.md` の「Model selection flags (L-size only)」を更新する (parallel with 1-4) (→ acceptance criteria 6):
   - `--opus`: `Use Opus (the \`opus\` alias, which resolves to the current Opus model) instead of the default Sonnet for design quality on L-size specs`
   - `--fable`: `Use Fable 5.1 (\`claude-fable-5-1\`, pinned by explicit model ID; Mythos class; opt-in, cost-sensitive — see \`docs/tech.md\` § Phase-specific model and effort matrix for cost/retention constraints)`
   - `--max`: `Override effort to \`max\` (Opus / Fable only)`
6. `docs/tech.md` の Phase-specific model and effort matrix 周辺を更新する (parallel with 1-5) (→ acceptance criteria 4):
   - 表の前の **Default parent = Sonnet 5** 段落を **Default parent = Sonnet 5.5** (`claude-sonnet-5-5`, launched 2026-09-28) に書き換え、`sonnet` エイリアスが Sonnet 5.5 に解決され、Sonnet 5 を置き換えたことを書く。**Scope of "Default parent"** 段落の `(Sonnet 5, Opus 5, or otherwise)` を `(Sonnet 5.5, Opus 5.5, or otherwise)` にする
   - その直後に新しい注記 **Alias resolution (as of 2026-10)** を追加する: Anthropic API での解決先 `sonnet` → Sonnet 5.5 (`claude-sonnet-5-5`)、`opus` → Opus 5.5 (`claude-opus-5-5`, 2026-09-22)、`fable` → Fable 5.1 (`claude-fable-5-1`, 2026-09-01; Claude apps gateway のセッションでは Fable 5)。解決先はプロバイダで異なる (例: Amazon Bedrock / Google Cloud では `sonnet` が Sonnet 4.5、Microsoft Foundry では `opus` が Opus 4.6) ことと、`--model` フラグが `ANTHROPIC_MODEL` より優先される (`run-*.sh` が両方を指定するのは `-p` モードの不具合対策) ことも書く。出典として Claude Code の model-config ページを挙げる
   - 表の `run-spec.sh` 行: Model 列 `Fable 5 via --fable` → `Fable 5.1 via --fable`、Effort 列 `Fable 5: high (default), max (explicit --max)` → `Fable 5.1: high (default), max (explicit --max)`
   - 新しい注記 **Sonnet 5.5 / Opus 5.5 / Fable 5.1 effort calibration** を **Opus 5 effort calibration** 注記の前に追加する。内容: (a) 公式の推奨 — Opus 5.5 は API・Claude Code とも既定 `medium`、同じレベルでも Opus 5 より多く考えるので Opus 5 の設定を持ち越さず sweep し直す。Sonnet 5.5 はレベルが再較正されており Sonnet 5 の設定を持ち越さない、まず `high` (明確な agentic coding は `medium`、難しく長いものは `high`)、`xhigh` / `max` は eval で効果が出た場合のみ。Fable 5.1 はまず `high` (既定)、能力が効く agentic / coding で `xhigh` / `max`。Claude Code は Opus 5.5 / Sonnet 5.5 の既定を `medium` にしているので、表で Effort が「—」の inline skill (triage / verify / auto / audit / doc) はセッション側で effort を指定しないと `medium` で動く。(b) Wholework の判断 — 表の明示 effort 値はこの Issue (#1485) では変えない。理由: 公式の推奨は「自分の eval で sweep する」で、5.5 / 5.1 世代での実測がまだ無い。#921 / #922 / #923 / #1064 と同じく、根拠となる実測が無いまま既定を変えない。(c) 再評価のきっかけ — 5.5 世代の spec / code / review の `token_usage` が溜まった時点で専用の再較正 Issue を立てる。特に `run-spec.sh` の Sonnet 経路 `max` と `--opus` 経路 `xhigh` は、5.5 の再較正後のレベルでは過剰になっている可能性が最も高い
   - **Opus 5 effort calibration** の冒頭に「(historical — applies to Opus 5; the `opus` alias now resolves to Opus 5.5, see the note above. Heading text retained because the #1064 entry below cites it by name)」を付ける
   - **Fable 5 (Mythos class)** 注記を **Fable 5.1 (Mythos class)** に書き換える: ID `claude-fable-5-1`。`fable` エイリアスもあるが、`run-spec.sh --fable` はコストに敏感な opt-in なので ID で固定する (Alias pin policy の意図的な例外)。コスト $10/$50 per MTok (Opus 5.5 の 2.5 倍、Sonnet 5.5 の 5 倍)、cache read は $0.25。30 日保持が必要で、Anthropic の明示的な許可が無い限り ZDR では使えない。プラン・シート種別によっては usage credits に課金される。Claude Code v2.1.257 以降が必要。拒否されたリクエストのフォールバック先として認められているのは Opus 4.8 と Opus 5 (Fable 5 の cyber → Opus 4.8 / biology → Opus 5 の記述をこれで置き換える)。参照先 `docs/reports/claude-fable-5-impact-strategy.md` は過去の分析として残す
   - **Sonnet 5** 注記の冒頭に「(historical — Sonnet 5 era; superseded as default parent by Sonnet 5.5)」を付ける
   - **Alias pin policy** の `rather than pinning explicitly to \`claude-sonnet-5\`` をモデル世代に依らない書き方 (`rather than pinning an explicit model ID such as \`claude-sonnet-5-5\``) にし、5.5 世代 (Sonnet 5.5 / Opus 5.5) がこの方針の下で 4 回目の自動採用になったこと、例外は `run-spec.sh --fable` の ID 固定だけで、`spawn-recovery-subagent.sh` の `claude-sonnet-4-6` 固定は #1485 でエイリアスに揃えたことを書く
   - **Opus 5 default parent evaluation — deferred** の末尾に、5.5 世代での状況を 1 文追記する: Opus 5.5 ($4/$20) は Sonnet 5.5 ($2/$10) の 2 倍で、再評価のきっかけ (i)(ii) はどちらもまだ起きていないので見送りを維持する
   - `SSoT note: Model values in run-*.sh use CLI aliases ...` 段落の直後に、commit trailer の方針を 1 段落追加する: Wholework の commit テンプレートはモデル名を含まない `Co-Authored-By: Claude <noreply@anthropic.com>` を使う。理由: `run-*.sh` や `append-consumed-comments-section.sh` など bash 側の commit はエイリアスがどのモデルに解決されたかを知る手段が無く、モデル名の直書きは世代交代のたびに古くなる (#918 で Sonnet 4.6 → Sonnet 5、#1485 で再発)
7. `docs/ja/tech.md` に Step 6 の変更を日本語で反映する (after 6)。`docs/translation-workflow.md` の Sync Procedure に従い、見出し・構造・書式を英語版と揃え、コードフェンス数が英語版と一致することを確認する (→ acceptance criteria 4)
8. 画像解像度・モデル名の古い記述を直す (parallel with 1-7):
   - `modules/browser-adapter.md` の「## Token budget」: `Claude Opus 4.7 supports images up to **2576 px** ...` を「Claude 4.7 and later models (including Opus 5.5 / Sonnet 5.5 / Fable 5.1) support images up to **2576 px** on the long edge (up to **4,784** visual tokens), compared to 1568 px on earlier models」の趣旨に変え、値は据え置く。`Coordinates are 1:1 with actual pixels on Opus 4.7` は「images within these limits are not downscaled, so coordinates are 1:1 with actual pixels; larger images are downscaled first」の趣旨に変える
   - `modules/lighthouse-adapter.md` の「## Notes」の **High-resolution model support** と、`modules/visual-diff-adapter.md` の「## Token Budget」の `up to 2576 px long edge on Claude Opus 4.7` も同じ趣旨で一般化する
   - `agents/review-bug.md` の **Note (cyber classifier)**: `currently resolves to Opus 5, which carries its own cyber classifier (...)` を「resolves to the current Opus via the alias (Opus 5.5 as of 2026-10); Opus 5 introduced its own cyber classifier (...) — do not assume Opus 5.5 behaves differently without checking」の趣旨に、Fable の文を「when running on Fable 5.1 (opt-in only), a refused request may fall back to Opus 4.8 or Opus 5」の趣旨に変える。「Do not evaluate security coverage assuming either classifier is inactive.」は残す
   - `SECURITY.md` の auto mode の段落: `Sonnet 4.6 or later, Opus 4.6 or later, or Fable 5` → `Sonnet 4.6 or later, Opus 4.6 or later, or a Fable model`
9. 確認を実行する (after 1-8) (→ acceptance criteria 7): `bats tests/run-spec.bats tests/spawn-recovery-subagent.bats tests/verify.bats tests/check-skill-body-hash.bats` が PASS、`bash scripts/check-skill-body-hash.sh` が exit 0、`python3 scripts/validate-skill-syntax.py` が PASS、`bash scripts/check-forbidden-expressions.sh` が PASS。既存スイートの PASS に加えて、Step 1 で追加した `spawn-recovery: claude -p is invoked with the sonnet alias (no pinned model ID)` と Step 3 で書き換えた `success: --fable switches model to claude-fable-5-1` が PASS していることを確認する

## Verification

### Pre-merge

- <!-- verify: file_not_contains "scripts/spawn-recovery-subagent.sh" "claude-sonnet-4-6" --> `scripts/spawn-recovery-subagent.sh` から `claude-sonnet-4-6` の固定が除かれ、他の `run-*.sh` と同じエイリアス指定に揃っている
- <!-- verify: file_contains "scripts/run-spec.sh" "claude-fable-5-1" --> `scripts/run-spec.sh --fable` が Fable 5.1 (`claude-fable-5-1`) を使い、モデル比較とコスト警告の文言も合わせて更新されている
- <!-- verify: rubric "tests/run-spec.bats の --fable テストが、モデル ID を完全一致で確認しており、claude-fable-5 のような古い ID では FAIL する形になっている" --> `tests/run-spec.bats` の `--fable` テストが、モデル ID を完全一致で確認している
- <!-- verify: rubric "docs/tech.md のモデルと effort の説明 (Phase-specific model and effort matrix 周辺) が、現行の Sonnet 5.5 / Opus 5.5 / Fable 5.1 を反映しており、エイリアスがどのモデルに解決されるかと、effort の推奨値の根拠が現行モデルについて書かれている" --> <!-- verify: file_contains "docs/tech.md" "Sonnet 5.5" --> `docs/tech.md` のモデルの記述が現行モデルに合っている
- <!-- verify: rubric "skills/ scripts/ modules/ の commit テンプレートにある Co-Authored-By trailer が、特定の古いモデル名 (Claude Sonnet 5 など) を直書きしておらず、実際に動いたモデルを反映する形か、モデル名を含まない形に統一されている" --> commit テンプレートの trailer に古いモデル名が直書きされていない
- <!-- verify: file_not_contains "skills/spec/SKILL.md" "Opus 4.x" --> `skills/spec/SKILL.md` の `--opus` / `--fable` の説明が現行モデルに合っている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> CI の bats テストが PASS している (PR route)

### Post-merge

- `claude -p --model sonnet --output-format json` と `--model opus` を実行し、出力に含まれるモデル ID がそれぞれ Sonnet 5.5 / Opus 5.5 であることを確認する (エイリアスが現行モデルに解決されることの確認) <!-- verify-type: manual -->
  - 手順例 (Claude Code のセッション内から実行する場合は `env -u CLAUDECODE` を付ける): `env -u CLAUDECODE claude -p --model sonnet --output-format json "Reply OK" | jq -r '.modelUsage | keys[]'` の出力に `claude-sonnet-5-5` が含まれ、`--model opus` では `claude-opus-5-5` が含まれること

## Notes

### Issue 本文と実装・現状の食い違い

- **`fable` エイリアスが存在する**: Issue 本文は「Fable は `opus` エイリアスでは届かず ID の明示が必要なので」と書いているが、Claude Code には `fable` エイリアスがあり、Anthropic API では Fable 5.1、Claude apps gateway のセッションでは Fable 5 に解決される (出所: https://code.claude.com/docs/en/model-config 、取得日時: 2026-10-03)。**対応**: `run-spec.sh --fable` は ID 固定 (`claude-fable-5-1`) を続ける。理由は (1) Pre-merge AC 2 が `claude-fable-5-1` の存在を求めている、(2) Fable はコストに敏感な opt-in で、解決先が環境で変わるエイリアスよりも ID 固定のほうがコスト警告の内容と実際のモデルが一致する、(3) Claude apps gateway ではエイリアスが Fable 5 に解決される。`fable` エイリアスがあることは `docs/tech.md` に書く (Step 6)
- **`ANTHROPIC_MODEL` と `--model` のどちらが優先されるか**: Issue 本文では未確認とされていたが、Claude Code の文書では `--model` フラグ (起動時) が `ANTHROPIC_MODEL` 環境変数より優先される (出所: 同上)。つまり `spawn-recovery-subagent.sh` は実際には `--model sonnet` で動いていたと考えられるが、`-p` モードの不具合対策として両方を指定する方針 (他の `run-*.sh` と同じ) を維持し、値を揃える
- **trailer の件数と場所**: Issue 本文は「`skills/` `scripts/` `modules/` に 20 箇所ほど」と書いているが、grep の実測は 20 箇所 / 12 ファイルで、うち 1 箇所は `agents/orchestration-recovery.md` (recovery plan の例)。同じ問題なので対象に含める

### 自動で決めた曖昧な点 (non-interactive mode)

- **commit trailer の形**: モデル名を含まない `Co-Authored-By: Claude <noreply@anthropic.com>` に統一する。理由: bash 側の commit (`run-spec.sh` / `run-code.sh` / `run-auto-sub.sh` / `append-consumed-comments-section.sh`) は LLM を介さず、エイリアスの解決先を知る手段が無い。SKILL.md 側だけ実行時のモデル名を使うと 2 つの形が混在する。モデル名の直書きは #918 (Sonnet 4.6 → Sonnet 5) に続いて 2 回目の古さ。他の案: 実行時のモデル名を使う (bash 側で実現できない)、`Claude Sonnet 5.5` に更新する (次の世代でまた古くなる)
- **Fable の指定方法**: ID 固定 (`claude-fable-5-1`) を続ける。上の「`fable` エイリアスが存在する」を参照。他の案: `fable` エイリアスに変える
- **effort の値**: 表の明示 effort 値は変えず、5.5 / 5.1 世代の公式の推奨と再評価のきっかけを `docs/tech.md` に書く。理由: 公式の推奨は「自分の eval で sweep する」で、根拠となる実測が無い。#921 / #922 / #923 / #1064 と同じ「実測が無いまま既定を変えない」判断。他の案: Opus 5.5 の推奨に合わせて `--opus` の `xhigh` を下げる、Sonnet 5.5 の推奨に合わせて spec の `max` を下げる
- **Issue に挙がっていないファイルを含めるか**: `agents/review-bug.md` (「currently resolves to Opus 5」)、`agents/orchestration-recovery.md` (trailer)、`SECURITY.md` (「or Fable 5」)、`docs/ja/tech.md` (翻訳の同期) を含める。どれも Issue の Purpose「モデルに関する文書と commit trailer の表記を実態に合わせる」と同じ種類の古さ
- **Post-merge の manual AC を自動化するか**: manual のまま残す。理由: 実際の `claude -p` 呼び出しは課金が発生し、エイリアスの解決先は実行環境のプロバイダで変わり (Bedrock / Google Cloud / Foundry では別のモデル)、`/verify` セッション内からの入れ子の `claude -p` には `CLAUDECODE` の扱いが要る。手順例は Post-merge に書いた

### 外部仕様の確認 (出所: すべて 2026-10-03 取得)

- モデル ID・リリース日・価格・既定 effort: https://platform.claude.com/docs/en/about-claude/models/overview 、https://platform.claude.com/docs/en/models/opus-5-5/overview (Opus 5.5: 2026-09-22、$4/$20、既定 `medium`)、https://platform.claude.com/docs/en/models/sonnet-5-5/overview (Sonnet 5.5: 2026-09-28、$2/$10、API の既定 `high`)、https://platform.claude.com/docs/en/models/fable-5-1/overview (Fable 5.1: 2026-09-01、$10/$50)
- Fable 5.1 の保持・フォールバック: https://platform.claude.com/docs/en/models/fable-5-1/whats-new-fable-5-1 (30 日保持、明示的な許可が無い限り ZDR 不可、フォールバック先として認められるのは Opus 4.8 と Opus 5)
- effort の推奨: https://platform.claude.com/docs/en/build-with-claude/effort (Opus 5.5 / Sonnet 5.5 / Fable 5.1 それぞれの推奨)
- エイリアスの解決先・優先順位・Claude Code での既定 effort・Fable 5.1 の CLI 要件 (v2.1.257 以降)・usage credits: https://code.claude.com/docs/en/model-config
- 画像解像度: https://platform.claude.com/docs/en/build-with-claude/vision (「Claude 4.7 and later models」が 2576 px / 4784 visual tokens。5.5 / 5.1 でも上限は変わっていない)。Issue の Notes にある「5.5 での上限を確認できた場合に更新する」に該当し、値は据え置いてモデル名の書き方を一般化する
- auto mode の対応モデル: https://code.claude.com/docs/en/permission-modes (Anthropic API では「Claude Opus 4.6 or later, Sonnet 4.6 or later, or a Fable model」)
- 未確認: Opus 5.5 の cyber classifier の挙動 (公式文書で見つからなかった)。`agents/review-bug.md` は「Opus 5.5 でも同じと決めつけない」書き方にする (Step 8)

### Exclusions (対象外)

- `scripts/watchdog-defaults.sh` のコメント (「Sonnet 5 で再較正」など): 履歴の記録 (Issue 本文で対象外と明記)
- `docs/spec/` `docs/reports/` `docs/ja/reports/` `docs/sessions/`: 過去の記録
- `docs/reports/event-log-schema.md` の `claude-sonnet-4-6`: `model` フィールドの値の例で、モデルの指定ではない
- `tests/run-issue.bats` / `tests/run-auto-sub.bats` の `claude-sonnet-5`: `modelUsage` のキーからモデル名を取り出すテストのデータで、モデルの指定ではない
- `modules/costly-step-protocol.md` / `modules/verify-patterns.md` / `modules/l0-surfaces.md` の Fable 5 / Sonnet 5 / `--fable`: 過去の事例 (#903, #939) の引用
- `docs/tech.md` の Sonnet 5 / Opus 5 effort 再較正の箇条 (#921 / #922 / #923 / #1064) と Watchdog の箇条: 過去の判断の記録として残す
- `docs/tech.md` の `frontend-visual-review` 行の「per Opus 5's recommended minimum」: #1063 の当時の根拠として残す

### その他

- **`skills/verify/SKILL.md` の hash マーカー**: CI の `Skill Body Hash check` (`scripts/check-skill-body-hash.sh`) と `tests/verify.bats` が `<!-- skill-body-sha: H -->` と本文の hash の一致を確認する。trailer の置き換えで hash が変わるので、Step 4 で再計算する
- **bats テストのデータ形式**: `tests/run-spec.bats` の mock `claude` は `$CLAUDE_CALL_LOG` に `MODEL_VALUE=<--model の次の引数>` と `ANTHROPIC_MODEL=<環境変数の値>` をそれぞれ 1 行で書く。`tests/spawn-recovery-subagent.bats` の新規テストも同じ形式のログを `$CLAUDE_ENV_LOG` に書く mock を使う。どちらも `grep -qx` で行全体を比べる
- **新しい分岐ロジック**: どの Step も既存スクリプトに新しい分岐を足さない (`run-spec.sh` の比較は値の置き換え)。テストの追加は回帰防止のため
- **fail-safe critical の判定**: `scripts/spawn-recovery-subagent.sh` は Tier 3 復旧で plan を検証するスクリプトだが、今回の変更は環境変数の値だけで制御フローは変えない。エイリアスが解決できない環境では `claude -p` が非ゼロで終わり、既存の `Error: claude -p exited with code ...` → `exit 1` の経路 (fail-closed) に入る。他の `run-*.sh` と同じ挙動
- **allowed-tools**: 新しいスクリプトは追加しない。変更する `modules/*.md` (`browser-adapter.md` / `lighthouse-adapter.md` / `visual-diff-adapter.md` / `doc-commit-push.md`) の変更箇所は `scripts/*.sh` を参照しないので、allowed-tools の更新は不要
- **audit/investigation 型か**: いいえ (既存の項目を分類して判断根拠を残す Issue ではない)
- **認証情報・セキュリティ方針**: 該当なし
- **Size の再評価**: 変更ファイルは 23 個 (Axis 1 では XL) だが、うち 12 個は trailer 1 行の機械的な置き換え、残りも大半が文書の更新 (Axis 2 で 1 段下げ) なので L のまま

## spec retrospective

### Minor observations
- Issue 本文の前提 (「Fable は ID の明示が必要」) は、Issue 作成後に Claude Code 側で `fable` エイリアスが入ったことで部分的に古くなっていた。モデル関連の Issue は前提の鮮度が短いので、`/spec` で公式文書を引き直す価値が高い
- trailer の対象を `skills/` `scripts/` `modules/` に限って grep すると `agents/orchestration-recovery.md` を取りこぼす。#918 の Spec はこのファイルを含めていたので、前例の Changed Files を見ると漏れに気付きやすい
- `skills/verify/SKILL.md` は `<!-- skill-body-sha: H -->` マーカーを持ち、1 行の文字列置き換えでも CI (`Skill Body Hash check`) と `tests/verify.bats` が落ちる。一括置換の対象にこのファイルが入るときは hash の再計算を Implementation Steps に明記する必要がある

### Judgment rationale
- commit trailer はモデル名を含まない形を選んだ。bash 側の commit は LLM を介さずエイリアスの解決先を知る手段が無く、「実行時のモデル名」は SKILL.md 側でしか実現できない。2 つの形が混在するより、1 つの形に統一するほうが単純で古くならない
- `run-spec.sh --fable` は `fable` エイリアスに切り替えず ID 固定を続けた。AC 2 が ID の存在を求めていることに加え、コスト警告の文言 (価格比) が特定のバージョンに結び付くため、エイリアスで解決先が変わるとコスト警告と実際のモデルがずれる
- effort の値は変えなかった。公式の推奨は「Opus 5.5 / Sonnet 5.5 では前世代の設定を持ち越さず sweep する」だが、Wholework にはまだ 5.5 世代の実測が無い。#921 / #922 / #923 / #1064 と同じ「実測が無いまま既定を変えない」方針に合わせ、推奨と再評価のきっかけを `docs/tech.md` に書くだけにした。特に `run-spec.sh` の Sonnet 経路 `max` と `--opus` 経路 `xhigh` は再較正の候補として最優先 (`/verify` での改善提案の材料)
- Issue に挙がっていない `agents/review-bug.md` / `SECURITY.md` / `docs/ja/tech.md` を対象に含めた。どれも Purpose と同じ種類の古さで、別 Issue に分けるほどの量ではない

### Uncertainty resolution
- `ANTHROPIC_MODEL` と `--model` の優先順位: Claude Code の model-config 文書で `--model` が優先と確認 (出所: https://code.claude.com/docs/en/model-config 、2026-10-03 取得)
- 5.5 / 5.1 での画像の上限: Vision 文書で「Claude 4.7 and later models」が 2576 px / 4784 visual tokens と確認 (出所: https://platform.claude.com/docs/en/build-with-claude/vision 、2026-10-03 取得)。値は据え置き
- Fable 5.1 の制約: 30 日保持・ZDR 不可・フォールバック先 (Opus 4.8 / Opus 5)・Claude Code v2.1.257 以降が必要、を確認 (出所: Fable 5.1 の What's new と model-config、2026-10-03 取得)
- 未解決: Opus 5.5 の cyber classifier の挙動は公式文書で見つからなかった。`agents/review-bug.md` は断定しない書き方にする
- 新しい分岐ロジックは無いが、回帰防止のテストを 2 つ用意する: `tests/spawn-recovery-subagent.bats` に `spawn-recovery: claude -p is invoked with the sonnet alias (no pinned model ID)` を追加、`tests/run-spec.bats` の `--fable` テストを `claude-fable-5-1` の完全一致 (`grep -qx`) に書き換え

## Phase Handoff

<!-- phase: spec -->

### Key Decisions
- commit trailer はモデル名を含まない `Co-Authored-By: Claude <noreply@anthropic.com>` に統一する (12 ファイル 20 箇所)。bash 側の commit はエイリアスの解決先を知れないため
- `run-spec.sh --fable` は `fable` エイリアスではなく `FABLE_MODEL_ID="claude-fable-5-1"` で固定し、代入と比較の両方でこの定数を使う
- `spawn-recovery-subagent.sh` は `ANTHROPIC_MODEL=sonnet` と `--model sonnet` の併記を維持する (他の `run-*.sh` と同じ `-p` モードの不具合対策)
- effort の明示値は変えず、5.5 / 5.1 世代の公式の推奨と再評価のきっかけを `docs/tech.md` に書く

### Deferred Items
- 5.5 世代での effort の再較正 (特に `run-spec.sh` の Sonnet 経路 `max` と `--opus` 経路 `xhigh`) — 実測が溜まってから別 Issue
- Post-merge の manual AC (エイリアスの解決先を `claude -p --output-format json` で確認) — merge 後に人が確認

### Notes for Next Phase
- `skills/verify/SKILL.md` の trailer を置き換えたら `<!-- skill-body-sha: H -->` を再計算する (`grep -v '<!-- skill-body-' skills/verify/SKILL.md | shasum -a 256 | cut -c1-8`)。忘れると CI の `Skill Body Hash check` と `tests/verify.bats` が落ちる
- `run-spec.sh` のコスト警告は既存テストが `credit` / `retention` の語を見ているので、この 2 語を残す
- `docs/tech.md` の「Opus 5 effort calibration」見出しは #1064 の箇条が名前で引用しているので、見出しの文字列は変えずに historical の注記を付ける
- `docs/ja/tech.md` の同期では英語版とコードフェンス数を合わせる (`docs/translation-workflow.md`)
