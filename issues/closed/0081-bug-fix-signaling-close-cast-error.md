# signaling DataChannel の close メッセージで `reason as String?` が cast エラーになると silent drop する

- Created: 2026-08-27
- Completed: 2026-08-31
- Branch: feature/fix-signaling-close-cast-error
- Polished: 2026-08-27
- Milestone: 2026.1.0

## 目的

signaling DataChannel 経由の `type: close` メッセージで `decoded['reason']` が String 以外の値だった場合に、`as String?` の同期例外が外側 try/catch で握りつぶされ、`SoraDisconnectedState` の発火と cleanup がスキップされるバグを修正する。

## 現状

`lib/src/sora_data_channel_controller.dart` の `SoraDataChannelController._handleSignalingDataChannelMessage` の `type == 'close'` 分岐は、`decoded['reason']` を `as String?` でキャストする。JSON 由来のため型は `Object?` である。数値・Bool・Map など String 以外の値が来ると `TypeError` を投げる。

外側の try/catch は `catch (error) { onDebugMessage('dc(signaling) json decode failed: error=$error'); }` としてこの例外を握りつぶし、`onSignalingClose(code, reason)` を呼ばずに return する。結果として `SoraConnection` の cleanup と `SoraDisconnectedState` emit がスキップされる。

`decoded['code']` は `Object?` のまま `onSignalingClose` に渡され、`_parseDisconnectCode`（`lib/src/sora_connection.dart`）が `int` / `String`（`int.tryParse`）以外を null 扱いにする型防御を既に持つため、code 側では cast エラーによる silent drop は発生しない。code 側の追加の型 defensive は不要である。

## 設計方針

- `decoded['reason']` は `is String` チェックを介して String または null に正規化する。`final reason = decoded['reason'] is String ? decoded['reason'] as String : null;` の形にする。
- `decoded['code']` は変更しない。`_parseDisconnectCode` が既に型防御しており、String コード（`int.tryParse` 可能）も受け入れているため、ここで型を絞ると既存挙動（String コードの close メッセージで closeInfo 付き disconnected）が退化する。
- 万一の想定外型（`reason` が String 以外）については `onDebugMessage` に「close message contains unexpected type」相当のログを残す。
- 外側 try/catch は現状維持し、cast 例外が silent drop される構造を残さない。型防御をロジック内で行い、`onSignalingClose` への到達を保証する。try ブロックの範囲は変更しない（`onSignalingClose` からの例外の帰着先が tail チェーンの `.catchError` に変わる挙動変更を避けるため）。

## 完了条件

- [x] `decoded['reason']` が String 以外の値でも `onSignalingClose` が呼ばれ、`SoraDisconnectedState` が発火する。
- [x] `decoded['code']` の既存の型防御（`_parseDisconnectCode`）は変更せず、String コードの close メッセージの挙動が維持される。
- [x] 上記シナリオを exercise するユニットテストを追加する。
- [x] 型不正時のデバッグメッセージが `onDebugMessage` 経由で観測できる。
- [x] `flutter analyze` と関連テストが成功する。

## 解決方法

`lib/src/sora_data_channel_controller.dart` の `_handleSignalingDataChannelMessage`
の `type == 'close'` 分岐で `decoded['reason']` を `as String?` で
キャストしていた行を、`is String` 型防御に置き換えた。JSON 由来の
`Object?` に対して `as String?` は String 以外の値で同期 TypeError を
投げ、外側 catch で握りつぶされて `onSignalingClose` が呼ばれなくなる
という silent drop を根絶する。

変更後は `final rawReason = decoded['reason'];` として一旦受け、
`rawReason is String ? rawReason : null` で String または null に正規化する。
想定外の型 (数値・Map など) が来たときは `onDebugMessage` に
「close message contains unexpected reason type: <runtimeType>」を
記録し、`onSignalingClose(code, null)` は必ず到達させる。

`decoded['code']` は変更していない。`_parseDisconnectCode`
(`lib/src/sora_connection.dart`) が `int` / `String` (`int.tryParse` 可能)
以外を null 扱いにする型防御を既に持つため、String コードの close
メッセージで closeInfo 付き disconnected を発火する既存挙動を維持する。

外側 try/catch の範囲は変更せず、cast エラーで silent drop になる構造
そのものを型防御ロジック側で排除した。

テストは `test/sora_data_channel_controller_test.dart` に新 group
`signaling close の reason 型防御` を追加し、次の 4 ケースを検証する。

- reason が数値 (int) → `onSignalingClose(4200, null)` が呼ばれ、
  「unexpected reason type: int」の debug ログが出る
- reason が Map → `onSignalingClose(code, null)` が呼ばれ、
  「unexpected reason type」の debug ログが出る
- reason が正常な String → そのまま `onSignalingClose` に渡り、
  警告 debug ログは出ない
- reason が null → そのまま null で渡り、警告 debug ログは出ない

テストは既存の依存注入 (`decodeJsonMap` を呼び出し側から差し替える)
パターンを使い、モック / スタブは使っていない。共有 factory 経由の
FFI 依存 (`WebrtcClient.create`) のため `ffiTestEnvironment.skipReason`
で skip 制御している。

`CHANGELOG.md` は `CODEBASE.md` の運用に従い触っていない (0072-0080 と同じ)。
