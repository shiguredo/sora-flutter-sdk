# `AudioCodecType.fromValue` / `SimulcastRequestRid.fromValue` / `SpotlightRid.fromValue` を削除する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/remove-unused-from-value
- Polished: 2026-09-07

## 目的

`lib/` 内部から呼び出しがなく、公開 API サーフェスとして残っている `AudioCodecType.fromValue` / `SimulcastRequestRid.fromValue` / `SpotlightRid.fromValue` を削除する。対応する `SoraRole` には `fromValue` が無く方針が揃っていないため統一する。まだ正式リリース前のため、公開 API であっても直接削除する。`CHANGELOG.md` への記載は行わない (`CODEBASE.md` の「正式リリース前」節に従う)。

## 現状

- `lib/src/sora_codec_type.dart` の `AudioCodecType.fromValue`
- `lib/src/sora_signaling_option.dart` の `SimulcastRequestRid.fromValue`, `SpotlightRid.fromValue`

は `lib/` 内部から呼び出しが無い。対応する `SoraRole` には `fromValue` が無く、`VideoCodecType.fromValue` だけが `WebrtcClient.supportedVideoCodecTypes` で使われている。方針が揃っておらず、無用な API サーフェスを増やしている。

ただし同一リポジトリ内の `devtools/lib/src/devtools_connection_controller.dart` の `buildSoraConnectionConfig` が削除対象の 3 つの `fromValue` を呼び出している (`AudioCodecType.fromValue`、`SimulcastRequestRid.fromValue`、`SpotlightRid.fromValue` の計 4 箇所)。`devtools` は `sora_sdk` に path 依存するインレポ消費者のため、削除と合わせて修正する。

該当 3 型は `lib/sora_sdk.dart` から export されているが、正式リリース前のため `@Deprecated` による段階的削除は行わず直接削除する。

## 設計方針

- `AudioCodecType.fromValue` / `SimulcastRequestRid.fromValue` / `SpotlightRid.fromValue` を直接削除する。
- `devtools/lib/src/devtools_connection_controller.dart` の `buildSoraConnectionConfig` における 4 箇所の呼び出しを、削除後の API で動く形に合わせて修正する (inline の `values` 探索など、`fromValue` に依存しない変換に置き換える)。
- 正式リリース前のため `@Deprecated` 付与の段階は挟まない。
- `CHANGELOG.md` への記載は行わない。
- 「必要が生じた場合に足す」方針を `CODEBASE.md` に明記する。
- `VideoCodecType.fromValue` は使用中のため残す。

## 完了条件

- [ ] 3 型の `fromValue` が削除されている。
- [ ] `devtools` の呼び出しが `fromValue` に依存しない形に修正されている。
- [ ] `CODEBASE.md` に「必要が生じた場合に足す」方針が明記されている。
- [ ] `lib/` 内部からの呼び出しが無いことを再確認済み。
- [ ] `lib/` と `devtools/` の `flutter analyze` と関連テストが成功する。
