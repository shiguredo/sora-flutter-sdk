# `CODEBASE.md` の「正式リリース前」節を現状の運用に合わせて更新する

- Created: 2026-08-31
- Completed: {YYYY-MM-DD}
- Branch: feature/update-codebase-md-release-flow
- Polished: {YYYY-MM-DD}

## 目的

`CODEBASE.md` の「正式リリース前」節が現状のリポジトリ運用と乖離している
問題を解消し、規約と実運用を一致させる。

## 現状

`CODEBASE.md` には次の記述がある。

```
## 正式リリース前

**正式リリース前**

- 正式リリース前は変更履歴を `CHANGES.md` に残さないこと
- 正式リリース前は Pull-Request を作らずブランチ作成から CI が通ったら develop にコミットしていくこと
  - 1 Issue 1 コミット 1 プッシュ
```

以下の 3 点で規約と実態がズレている。

- 実ファイルは `CHANGELOG.md` である (`CHANGES.md` は存在しない)。
- `CHANGELOG.md` には既に `## 2026.1.0`（リリース日: 2026-08-25）が存在し、
  正式リリース済みの状態である。「正式リリース前」条項の適用可否が曖昧に
  なっている。
- 直近の bug fix (0072 / 0073 / 0074 / 0076 / 0077 / 0078) の運用は
  「Pull-Request なし + `CHANGELOG.md` 未更新 + develop 直接コミット」で
  継続しており、「正式リリース前」条項をそのまま準用している。

新規に issue を対応するエージェント (`/auto-resolve`) が起動時に規約と
実運用のどちらに従うか判断できない状態になっている。

## 設計方針

- `CODEBASE.md` の該当節を書き換え、以下を明確化する。
  - 変更履歴ファイル名を `CHANGELOG.md` に修正する。
  - 「Pull-Request を作らずに develop 直接コミットする」運用が、正式リリース
    後 (2026.1.0 リリース済) も継続適用されるかどうかを明記する。
  - `CHANGELOG.md` への追記方針を、breaking change / bug fix / 機能追加
    それぞれで書くタイミングと合わせて再定義する。
- 表現は shiguredo-changelog / shiguredo-git スキルとの矛盾が起きないよう
  整合を確認する。

## 完了条件

- [ ] `CODEBASE.md` の該当節が現在の実運用と一致している。
- [ ] `CHANGES.md` への言及が削除され、`CHANGELOG.md` に統一されている。
- [ ] 正式リリース後の運用ルール (PR の要否、`CHANGELOG.md` 追記の要否)
      が明確に書かれている。
