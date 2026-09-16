# 公開 API 間の `textureId` semantics 分裂を解消する

- Created: 2026-08-31
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-texture-id-semantics
- Polished: {YYYY-MM-DD}

## 目的

同じ「local video texture id」を表す 3 つの公開 API が、それぞれ異なる型と
エラー契約を持ち、消費側 (devtools / 3rd-party) が external track を扱う
たびに外部ガードを書かされている状態を解消し、統一的な契約に寄せる。

## 現状

`lib/src/sora_local_video_handle.dart` の `SoraLocalVideoHandle.textureId`、
`lib/src/sora_video_widget.dart` の `SoraLocalVideoWidget.textureId`、
`lib/src/sora_media_stream.dart` の `LocalVideoTrack.textureId` の 3 者で
契約が分裂している。

- `SoraLocalVideoHandle.textureId`: `int`。`SoraConnection.localVideo`
  Stream 経由では常に非負が届く (external では emit 自体がスキップされる)。
- `SoraLocalVideoWidget.textureId`: `int?`。widget パラメータとして null と
  負値のときは placeholder に落とす防御を持つ。
- `LocalVideoTrack.textureId`: `Future<int>`。external では `StateError` を
  投げる。

`devtools/lib/src/devtools_connection_controller.dart` などの消費側では、
external を扱うたびに `if (!request.useExternalVideoTrack) ...` のような
外部ガードを各 callsite に書いている。3 者の意図 (「値がない」を Stream 側
スキップ / null / 例外 のいずれで表すか) が揃っていないため、SDK 利用者が
毎回どの API がどの契約で振る舞うかを覚え直す必要がある。

## 設計方針

- 3 者の「external の扱い」を 1 つに寄せる方針を決める。以下の候補から
  ユーザー確認を経て選ぶ:
  - (a) null で「値の不在」を表現し、`LocalVideoTrack.textureId` も
    `Future<int?>` に変える (Stream 側は emit するが textureId=null を渡す)。
  - (b) 例外で表現し、`SoraLocalVideoHandle.textureId` も getter 化して
    `StateError` を投げる (Stream 側の emit も維持)。
  - (c) 現状の「Stream スキップ + Future<int> の例外」を維持し、消費側で
    書く外部ガードを SDK が提供するヘルパ (例: `LocalVideoTrack.hasTextureId`) に
    抽出する。
- どの選択肢を採用しても公開 API の破壊的変更を伴う可能性があるため、
  `CHANGELOG.md` の記載方針 (別 issue) と合わせて決定する。
- 選択肢を確定させた上で、`devtools/lib/**` と `e2e_test_app/**` の
  該当箇所をすべて追随させる。

## 完了条件

- [ ] 3 つの API の `textureId` 契約が統一されている (同じ「値なし」の
      表現方法が使われている)。
- [ ] `devtools/lib/**` と `e2e_test_app/**` の該当消費側がすべて追随する。
- [ ] `flutter analyze` と関連テストが成功する。
- [ ] 破壊的変更を伴う場合も、正式リリース前のため `CHANGELOG.md` には記載しない (`CODEBASE.md` の運用に従う。破壊内容は本 issue に記録する)。

## pending にする理由

候補 (a)(b)(c) のいずれも現状では成立しないため、設計判断待ちとして pending とする。polish 時の実ファイル照合で判明した点は以下である。

- (a) は `SoraLocalVideoHandle.textureId` の `int` → `int?` 変更に触れておらず型レベルで不完全であり、`0078` で却下済みの案の再掲である (却下理由への反論なし)。
- (b) の「Stream 側の emit も維持」がスキップ維持か throw する Handle の emit か不明であり確定できない。
- (c) は現状維持であり、本 issue の統一目的・完了条件と両立しない。
- `Widget.textureId` (`int?` 入力パラメータ) を産出側 2 者と同列に統一することはできない。統一対象は 2 産出者に絞る再定義が必要である。
- `0149` (解除通知) は別 Stream 追加で単独実施可能となり、本 issue への依存を解消した。`0111` (結合点凍結)・`0146` (現行 `int` 前提) とは相互依存が残る。再開時は残依存の順序を定めること。
