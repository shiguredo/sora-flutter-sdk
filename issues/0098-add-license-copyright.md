# `LICENSE` に Copyright 行 / APPENDIX を追加する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/add-license-copyright
- Polished: 2026-09-07
- Milestone: 2026.1.0

## 目的

`LICENSE` に Apache License 2.0 の APPENDIX boilerplate と Copyright 行が無く、`LICENSE` ファイル単体からは著作権者が読み取れない状態を解消する。

## 現状

`LICENSE` は Apache License 2.0 本文のみで、`END OF TERMS AND CONDITIONS` (177 行目) で終了し、その後の APPENDIX boilerplate が付いていない。

リポジトリ内の著作権者表記は `README.md` 513-531 行目のライセンス節に `Copyright 2026-2026, Shiguredo Inc.` として存在する。`LICENSE` ファイル単体には所有者名の記載が無い。`pubspec.yaml` に著者名フィールドは無く (`name` / `description` / `repository` / `homepage` / `topics` のみ)、照合対象は `README.md` とする。

## 設計方針

- `LICENSE` の末尾 (`END OF TERMS AND CONDITIONS` の後) に、`README.md` 518-530 行目と同一文面の boilerplate を追記する:
  ```text
  Copyright 2026-2026, Shiguredo Inc.

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

      http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
  ```
- 表記 (年範囲・カンマ) は `README.md` の既存表記に合わせる。新規の NOTICE ファイルは作らない。
- 挙動変更なし。`LICENSE` のみの修正。

## 完了条件

- [ ] `LICENSE` 末尾に上記 boilerplate が追記されている。
- [ ] 追記文面が `README.md` 518-530 行目と同一である。
