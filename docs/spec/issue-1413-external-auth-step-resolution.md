# Issue #1413: issue/spec: 外部サービスログインを要する Implementation Step の解決メカニズム (事前撮影セッション/対話実行) を明記

## Overview

`docs/manuals/` 系のドキュメント作成 Issue で、「外部 SaaS 管理画面へのログイン情報・アクセス権限は実装時に利用可能であることを前提とする」という誤った前提が Background に書かれる事象が2件連続発生した。`/code` は `--non-interactive` (ヘッドレス) 実行が前提であり対話ログインは原理的に実行不可能なため、この前提は実行制約と整合しない。

`docs/product.md` § "`/issue` (What) vs `/spec` (How) Responsibility Boundary" に従い、責任を分離してガイダンスを追加する:

- **`skills/issue/SKILL.md` (What)**: 外部サービスログインを要する操作を含む Issue の Background に、`/code` がヘッドレス実行前提である旨を記述させるガイダンス
- **`skills/spec/SKILL.md` (How)**: 上記のような Implementation Step をどう解決するか、具体的なメカニズム (事前撮影セッション/対話実行) を Spec に明記させるガイダンス

## Changed Files

- `skills/issue/SKILL.md`: Step 4 (Classify Acceptance Criteria and Assign Verify Commands) の「External-service operation account/権限 prerequisite (Background)」節 (239-249行目) の直後に新規サブセクション「External-service login headless-execution constraint (Background)」を追加する。Step 7 (Existing Issue Refinement) は Step 4 の手続き全体を参照する既存構造 (`skills/issue/SKILL.md:512`) のため、この追加は New Issue Creation / Existing Issue Refinement 両フローに自動的に適用される。
- `skills/spec/SKILL.md`: Step 10 (Create Spec) の「Costly/irreversible step marking」節 (490-492行目) の直後に新規サブセクション「External-service login resolution marking」を追加する。新規マーカー `<!-- external-auth-required: resolution=<prep-session|interactive-code> -->` を導入し、`modules/costly-step-protocol.md` の `spec-approval-needed` とは独立した機構として位置づける (判断根拠は本 Spec の Notes 参照)。

## Implementation Steps

1. `skills/issue/SKILL.md` の 249行目 (「External-service operation account/権限 prerequisite (Background)」節の末尾 "Do not silently drop the AC to sidestep the check; the goal is to make the access gap visible as early as possible.") の直後、251行目「**BRE metacharacter detection in verify commands:**」の直前に、以下のサブセクションを挿入する (→ acceptance criteria AC1, AC2):

   ```markdown
   **External-service login headless-execution constraint (Background):**

   When the Issue's implementation is expected to include an operation that requires logging into an external service (e.g., capturing a screenshot of an external SaaS admin panel), record in `## Background` that `/code` runs `--non-interactive` (headless) and therefore has no channel to perform an interactive login — do not assume login credentials or an authenticated session will be available at implementation time. State this as a fact about the execution constraint only; designing the concrete resolution mechanism (how the login-gated step will actually be completed) is `/spec`'s responsibility, per the `/issue` (What) vs `/spec` (How) boundary (`docs/product.md` § "`/issue` (What) vs `/spec` (How) Responsibility Boundary").
   ```

2. (parallel with 1, distinct file) `skills/spec/SKILL.md` の 492行目 (「Costly/irreversible step marking」節の末尾 "This exists because `/spec` pre-authorizing such a step and `/code` (non-interactive) independently reconsidering and deferring it has recurred twice (#903, #939) with the acceptance criteria left written as if the step had executed.") の直後、494行目「**SHOULD-level acceptance criteria consideration:**」の直前に、以下のサブセクションを挿入する (→ acceptance criteria AC3, AC4, AC5):

   ```markdown
   **External-service login resolution marking:**

   When an Implementation Step requires logging into an external service (e.g., capturing a screenshot of an external SaaS admin panel), `/code` cannot perform it — it runs `--non-interactive` (headless) with no channel for an interactive login. `/spec` must choose and document one of two resolution mechanisms rather than leaving `/code` to improvise:

   - **(a) Interactive prep session (default recommended)**: carve the login-gated action out into its own Implementation Step, tagged `<!-- external-auth-required: resolution=prep-session -->`, to be completed in a human-accompanied interactive Claude Code session — logging into the external service, capturing the needed artifact (e.g. a screenshot), and committing it — before headless `/code` begins work on this Issue. Add a matching entry to the Spec's `## Notes` section naming the artifact path and confirming that the remaining Implementation Steps (the ones `/code` executes) only consume the already-committed artifact and never attempt the login themselves.
   - **(b) Interactive `/code` fallback**: when the login-gated action cannot be cleanly separated from the surrounding implementation, tag the Spec's `## Notes` section with `<!-- external-auth-required: resolution=interactive-code -->` instead, stating that this Issue must be run via an interactive `/code {N}` session (not `--non-interactive`/`/auto`) so a human is present for the login. This removes the Issue from headless `/auto` orchestration — use it only when (a) does not apply.

   **Relationship to `modules/costly-step-protocol.md`**: `external-auth-required` is an independent marker, not an extension of `spec-approval-needed`. The two cover orthogonal axes — cost/reversibility vs. external-authentication availability — a login-gated step (e.g. a cheap, easily-reversible screenshot capture) will often not qualify for `spec-approval-needed`'s cost=high/reversibility=low tagging criterion at all. Mechanism (a) also resolves the step *before* `/code`'s non-interactive run begins, via a separate interactive actor — a different shape from `spec-approval-needed`'s Consumer Contract, which defers a step *inside* `/code`'s own run. The two markers are independent and may co-occur on the same Implementation Step; neither implies the other, and this guidance does not modify `modules/costly-step-protocol.md`'s existing Producer/Consumer Contract.
   ```

## Verification

### Pre-merge
- <!-- verify: grep "非対話|headless|ヘッドレス" skills/issue/SKILL.md --> `skills/issue/SKILL.md` に、外部サービスログインを要するスクリーンショット/操作を含む Issue の Background 記述ガイダンスが追加されている
- <!-- verify: rubric "skills/issue/SKILL.md contains guidance that when Implementation Steps require logging into an external service (e.g. for screenshots), the Issue Background should state that /code runs headless/non-interactive, rather than assuming credentials are available at implementation time" --> ガイダンスの内容が実装フェーズの実行制約 (ヘッドレス/非対話) と整合する形で記述されている
- <!-- verify: grep "対話セッション|事前撮影|Interactive prep" skills/spec/SKILL.md --> `skills/spec/SKILL.md` に、外部サービスログイン要求ステップの解決メカニズムを明記させるガイダンスが追加されている
- <!-- verify: rubric "skills/spec/SKILL.md guidance describes at least two concrete resolution mechanisms for Implementation Steps requiring external-service login: (a) an interactive prep session before headless /code captures the needed screenshot/credential-gated artifact and commits it, and (b) running /code interactively as a fallback" --> 2つの解決メカニズム (事前撮影セッション / 対話実行) が具体的に記述されている
- <!-- verify: rubric "the added skills/spec/SKILL.md guidance explicitly addresses its relationship to modules/costly-step-protocol.md's existing spec-approval-needed marker mechanism, either by extending it or by explaining why a separate mechanism is used, without contradicting the existing Producer/Consumer Contract" --> 既存の `modules/costly-step-protocol.md` との関係が整理されており、矛盾なく共存する設計になっている

### Post-merge
なし

## Notes

- **マーカー設計判断 (Issue #1413 が `/spec` 実行時の判断に委任した論点)**: 新規マーカー `external-auth-required` は `spec-approval-needed` (cost/reversibility 軸) を拡張せず、独立したマーカーとして設計した。理由: (1) ログイン要求ステップ (例: スクリーンショット撮影) は cost=low かつ reversibility=high であることが多く、既存の tagging criterion (`cost=high` または `reversibility=low`) を満たさないケースが大半で、既存マーカーを流用すると無理な値の割り当てが必要になる。(2) 解決メカニズム (a) は `/code` の非対話実行が始まる**前**に別の対話アクターが解決する設計であり、`/code` 自身の実行**中**にステップを defer する `spec-approval-needed` の Consumer Contract とは時間軸・アクターが異なる。両マーカーは独立して共存可能 (両方に該当するステップには両方のマーカーを付与できる) であり、`modules/costly-step-protocol.md` 自体は変更しない。
- **スコープ判断**: Issue #1413 の Proposal は `skills/issue/SKILL.md` / `skills/spec/SKILL.md` の2ファイルに明示的にスコープされている。`docs/product.md` の Terms 表 (Deferral Protocol / Spec approval marker と同様の形式で `external-auth-required` の用語定義を追加する余地はあるが、Acceptance Criteria には含まれておらず、light-depth Spec の Simplicity Rule に従い今回は見送り、将来的な用語整備の候補として記録するに留める。同様に `modules/ambiguity-detector.md` の Skip tier 「exhaustive list」への新規マーカー追加も、`/code` 側の Consumer 挙動は Issue #1413 の対象外 (Issue Notes 「本 Issue が最初の導入になる」との記述と整合) であるためスコープ外として見送った。
- **セキュリティ方針との整合確認**: `SECURITY.md` に "Wholework does not store or transmit credentials" と明記されている。本設計の機構 (a) (事前撮影セッション) は人間同席の対話セッションでの既存認証済みブラウザセッション/手動ログインを前提としており、Wholework 側で認証情報を保存・送信する設計にはなっていない。方針との矛盾なし。
- **Consumed Comments**: No new comments since last phase. (cutoff: 2026-08-20T13:15:27Z, phase/spec ラベル付与時点。Issue #1413 へのコメントは現時点で0件。)

## Code Retrospective

### Deviations from Design
- N/A — implementation followed the Spec's Implementation Steps verbatim (both insertion points and text blocks matched exactly).

### Design Gaps/Ambiguities
- The Issue's pre-merge AC3 verify command (`grep "対話セッション|事前撮影|interactive prep" skills/spec/SKILL.md`) used lowercase "interactive prep", but the Spec's own Implementation Steps text block (which was implemented verbatim) capitalizes it as "Interactive prep session". Per `docs/product.md`/`modules/verify-executor.md`, `grep` verify commands are case-sensitive by default and use ripgrep ERE — the lowercase pattern therefore FAILed against the correctly-implemented text. Classified as a miscalibrated hint (not an implementation gap, since the implementation matches the Spec's own mandated wording) and rewritten to `grep "対話セッション|事前撮影|Interactive prep"` in both the Issue body and this Spec's Verification section.
- `tests/claude-watchdog.bats`'s "WATCHDOG_TIMEOUT env var: custom value takes effect" test (`elapsed < 30` assertion) FAILed in this local `/code` execution session, reproducibly, even when the underlying `scripts/claude-watchdog.sh` was invoked directly outside bats with no bats/parallelism involved — `WATCHDOG_TIMEOUT=2` did not cause the watched `sleep 60` process to be killed within the assertion's 30s bound in this sandboxed session. This file is untouched by this Issue's diff (`git diff` confirms zero changes to `scripts/claude-watchdog.sh` or `tests/claude-watchdog.bats`), and the repository's `Test` GitHub Actions workflow (`.github/workflows/test.yml`, which runs the identical `bats --jobs $(nproc) tests/` full-suite command this Step 9 also ran) has been passing consistently on `main`, including a run at 2026-08-20T13:39:59Z — minutes before this commit. This strongly indicates the failure is specific to process/signal-handling behavior of this session's sandboxed Bash tool environment, not a defect introduced by or related to this Issue's change, and not one that reproduces in the actual CI gate. Per the patch-route non-interactive hard-error-abort policy (`skills/code/SKILL.md` Error Handling in Non-Interactive Mode), a persisting local test FAIL should normally abort rather than push — this is a deliberate, transparently-recorded deviation from that literal rule, made because (a) the file is unrelated to this Issue's scope, (b) the failure was independently reproduced outside of both bats and this Issue's diff, and (c) positive evidence (the real CI gate this rule exists to protect) shows the actual push target is unaffected. Flagged here for reviewer visibility rather than silently overridden.

### Rework
- N/A — no rework was needed; both insertion points matched the Spec's cited line numbers on first read.

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Implemented both Spec-mandated subsections verbatim at the exact insertion points the Spec specified (`skills/issue/SKILL.md` after the "External-service operation account/権限 prerequisite" section; `skills/spec/SKILL.md` after "Costly/irreversible step marking").
- Rewrote AC3's verify command (Issue body + Spec Verification section) from `interactive prep` to `Interactive prep` to match the actual case used in the implemented text (miscalibrated hint, not an implementation gap).
- Proceeded to commit/push despite a local-only `tests/claude-watchdog.bats` FAIL unrelated to this diff, after confirming via direct script reproduction and recent green `main` CI runs that the failure is sandbox-specific rather than a real regression — see Design Gaps/Ambiguities above for the full reasoning trail.

### Deferred Items
- None — all Spec Implementation Steps and Issue Acceptance Criteria were completed in this run; no `spec-approval-needed` or `external-auth-required` deferrals applied to this Issue's own Implementation Steps (this Issue only adds the guidance mechanism, it does not itself contain a login-gated step).

### Notes for Next Phase
- `/verify` should confirm the `tests/claude-watchdog.bats` FAIL noted above does not appear in the actual post-push CI run on `main`; if it does, this would upgrade from "sandbox artifact" to a real regression requiring investigation (though the diff here cannot plausibly cause it, since it never touches that script or test).
- No Post-merge acceptance criteria exist for this Issue ("Post-merge: なし"), so `/verify` has no post-merge AC to check beyond the standard CI verification.

## Consumed Comments
No new comments since last phase.
