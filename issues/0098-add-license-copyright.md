# `LICENSE` に Copyright 行 / APPENDIX を追加する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/add-license-copyright
- Polished: {YYYY-MM-DD}
- Milestone: 2026.1.0

## 目的

`LICENSE` に Apache License 2.0 の APPENDIX と Copyright 行が無く、リポジトリ内から著作権者が読み取れない状態を解消する。

## 現状

`LICENSE` は Apache License 2.0 本文のみで、`END OF TERMS AND CONDITIONS` の後の APPENDIX（`Copyright <year> <owner>` の boilerplate 例示）が付いていない。Apache 2.0 は「著者が誰であるか」の明示（NOTICE）を実質前提としており、通常の LICENSE ファイルは末尾に:

```
   Copyright 2026 Shiguredo Inc.

   Licensed under the Apache License, Version 2.0 ...
```

の boilerplate 付与を推奨している。現状ではライセンスファイルから「Sora Flutter SDK の著作者が Shiguredo であること」が読み取れない。

## 設計方針

- `LICENSE` の末尾に Apache License 2.0 の APPENDIX 節を追記する。
- Copyright 行は `Copyright 2026 Shiguredo Inc.` とする。年は最初のリリース年（2026）に合わせる。
- pubspec.yaml / README との整合（著者名 / 会社名）を確認する。

## 完了条件

- [ ] `LICENSE` 末尾に APPENDIX 節と `Copyright 2026 Shiguredo Inc.` が追記されている。
- [ ] pubspec.yaml / README の著者名と整合している。
