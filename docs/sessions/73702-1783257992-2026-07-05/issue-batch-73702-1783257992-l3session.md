# L3 Session Bridge: batch-73702-1783257992

## Auto Retrospective

### Improvement Proposals

- **/verify SKILL に「documented deferral」escape hatch を追加**: 現行 SKILL は tier-gated auto-retry の発火条件を tier + config + iteration count のみで判定しており、FAIL の性質 (実装バグ vs 意図的 deferral) を区別していない。documented deferral の場合、`/code` 再実行は同じ deferral を反復するだけで compute を浪費する。改善案: (a) FAIL marker comment に `deferral=true` marker を追加し、`/verify` が検出したら auto-retry を skip する、または (b) Spec の Verification section に `<!-- known-deferral: reason=... -->` を認める形式を導入し、`/verify` がこれを検出したら FAIL 扱いだが auto-retry を skip する。
- **AC 設計時の "実測依存 rubric" ガイドライン追加**: 本 session の #939 のように AC が「実測データの存在」を条件とする場合、`/issue` フェーズで「実測が実施されない場合の deferral protocol」も同時に定義することを推奨するガイドラインを `modules/verify-patterns.md` に追加すべき。現状は AC 完全達成のみが verify PASS 基準となるため、意図的 deferral が structural に不整合を生じる。
