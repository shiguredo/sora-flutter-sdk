# テスト名の日英混在を日本語に統一する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/fix-test-names-japanese
- Polished: {YYYY-MM-DD}

## 目的

AGENTS.md line 13「テストのログメッセージは全て日本語にすること」に反し、`test('...')` 名称が英語で書かれているテストを日本語に統一する。`test(...)` の名称はテスト実行時のログとして表示されるため対象に含まれる。

## 現状

以下のテストファイルで英語のテスト名が確認されている:

- `test/sora_connection_config_test.dart`: `'SoraConnectionConfig serializes flat media options to a standard codec friendly map'`, `'SoraConnectionConfig uses sensible defaults'`
- `test/simulcast_video_encoder_factory_test.dart`: `'does not crash with nullptr'` 等 6 件
- `test/sdp_negotiation_test.dart`: `'offer -> offer: old emits nothing, new emits answer'` 等 6 件
- `test/webrtc_client_test.dart`: `'closePeerConnection completes pending getStats Future with StateError'` 等 3 件

同じファイル内で日本語 test 名と英語 test 名が混在しているケースもある（例: `webrtc_client_test.dart` は `closePeerConnection clears pending getStats tracking` の直下に `closePeerConnection は native stats リソースを孤立 request へ移す` が並ぶ）。

## 設計方針

- 該当テスト名をすべて日本語に書き換える。
- 単純な直訳ではなく、テストが何を検証しているかが読み取れる自然な日本語に整える。
- 同ファイル内の他日本語テストと語彙・書き方を揃える。
- `group` 名も同じ規約で日本語化する。
- 挙動変更はなく、命名のみの修正。

## 完了条件

- [ ] `test/` 配下のすべての `test(...)` / `group(...)` 名が日本語である。
- [ ] 内容から検証対象が読み取れる自然な日本語になっている。
- [ ] `flutter analyze` と関連テストが成功する。
