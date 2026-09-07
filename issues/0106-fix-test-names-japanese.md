# 純粋英文のテスト名・グループ名を日本語に統一する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/fix-test-names-japanese
- Polished: 2026-09-07

## 目的

AGENTS.md line 13「テストのログメッセージは全て日本語にすること」に反し、`test('...')` / `group('...')` 名称が純粋英文で書かれている箇所を日本語に統一する。本 issue では `test` / `group` 名を line 13 の対象と解釈する (`0104` / `0135` と同解釈)。`flutter test` のレポーター出力で名称が表示されるため対象に含まれる。

## 現状

日本語を含まない純粋英文の名称は以下 21 件である:

- `test/sora_connection_config_test.dart`: `test` 2 件 (5-6, 52 行目)
- `test/simulcast_video_encoder_factory_test.dart`: `test` 6 件 (25, 32, 50, 72, 79, 87 行目)、`group` 2 件 (24, 65 行目)
- `test/sdp_negotiation_test.dart`: `test` 6 件 (159, 182-183, 210, 232, 254, 272-273 行目)
- `test/webrtc_client_test.dart`: `test` 3 件 (16-17, 39, 100 行目)、`group` 2 件 (15, 99 行目)

対象外とする:

- 関数名・クラス名そのままの `group` 名 (例: `parseSignalingUrl`、`SoraErrorCode`)。被験体との対応付け (トレーサビリティ) のため維持する。
- 日本語を含む混在名 (例: `SdpNegotiationCallbacks race 再現`)。既に日本語を含むため対象外とする。

同じファイル内で日本語 test 名と英語 test 名が混在しているケースもある（例: `webrtc_client_test.dart` は英語名の `group` 内に日本語テストが並ぶ）。

## 設計方針

- 上記 21 件を日本語に書き換える。
- 単純な直訳ではなく、テストが何を検証しているかが読み取れる自然な日本語に整える。コード識別子・固有名詞 (関数名・クラス名・`StateError` 等) は残してよい (`0112` と同等の基準)。
- 同ファイル内の他日本語テストと語彙・書き方を揃える。
- `0135` (test/ 分割) の確定を待たず、現行配置で実施する。分割時は改名後の名称を引き継ぐ。
- 挙動変更はなく、命名のみの修正。

## 完了条件

- [ ] 上記 21 件の名称が日本語 (コード識別子・固有名詞を除く) になっている。
- [ ] 内容から検証対象が読み取れる自然な日本語になっている。
- [ ] `flutter analyze` と `flutter test test/` が成功する。
