# notify / push / switched の payload を専用型へ整理する

- Priority: Medium
- Created: 2026-04-07
- Model: GPT-5.4 Codex
- Polished: 2026-06-05

## 目的

`SoraConnectionEvent` へ統合した `notify` / `push` / `switched` は、現在も `Map<String, Object?>` のまま payload を保持している。これを専用型へ整理し、イベント種別だけでなく payload も型安全に扱える公開 API へ更新する。

## 優先度根拠

`SoraConnectionEvent` の導入により、イベント種別自体は `sealed class` で判別できるようになった。一方で `notify` / `push` / `switched` の payload は `Map<String, Object?>` のままであり、利用側はキー文字列と実行時 cast に依存し続ける。

この構成では、イベントの分岐は compile time に検査できても、payload の必須項目や値型の誤りは実行時まで検出できない。特に `notify` の `event_type` や `connection_id`、`switched` の `ignore_disconnect_websocket` のような利用頻度の高い項目は、公開型として契約を持たせた方が扱いやすい。

一方で、過去のイベント統合 issue では「順序付き観測を 1 本にまとめること」を優先し、message schema の型安全化は意図的に切り離した。今回の issue は、その見送った論点を個別に扱うために必要である。

## 現状

- 統合 stream は `Stream<SoraConnectionEvent>` として実装済み（過去のイベント統合 issue で完了）
  - 派生型の命名規則はイベント統合 issue の当初案である `<意味>ClientEvent` ではなく、実装では `Sora<意味>Event`（例: `SoraNotifyEvent`, `SoraPushEvent`, `SoraSwitchedEvent`）になっている
  - 本 issue の「対応内容」に書かれている `SoraNotifyClientEvent` / `SoraPushClientEvent` / `SoraSwitchedClientEvent` は現状の実装名と一致していないため、対応時に読み替える必要がある
- `lib/src/sora_connection_event.dart`
  - `SoraNotifyEvent.message: Map<String, Object?>`
  - `SoraPushEvent.message: Map<String, Object?>`
  - `SoraSwitchedEvent.message: Map<String, Object?>`
  - いずれも raw payload のまま公開されており、型安全化は未着手

## 設計方針

1. `notify` / `push` / `switched` 用の公開型を追加する
2. `SoraNotifyEvent` / `SoraPushEvent` / `SoraSwitchedEvent` の payload を `Map<String, Object?>` から専用型へ置き換える
3. 必須項目と任意項目を整理し、どこまで public API の契約に含めるかを定義する
4. example の参照コードを専用型ベースへ更新する
5. `CHANGES.md` に API 変更として記載する

## 注意点

- Sora signaling の message schema をすべて固定化すると拡張しにくくなるため、専用型で持つ項目と raw payload を併存させるか検討が必要である
- `notify` は `event_type` ごとに構造差があるため、単一型で持つか、イベント種別ごとの派生型へ分けるかを整理する必要がある
- 今回の issue は payload の型安全化が目的であり、`remoteVideo` / `localVideo` 系の統合や source 間の厳密順序保証は対象外である

## 完了条件

- 専用型と raw payload（`Map<String, Object?>`）の併存方針が決まっている
- `notify` の単一型 / 派生型の方針が決まっている
- 公開 API 契約の線引きが決まっている

## pending 理由

本 issue は設計判断が必要なため、実装着手前に方針を固める必要がある。以下が未確定である。

- 専用型と raw payload（`Map<String, Object?>`）の **併存方針**
  - Sora の signaling message schema は Sora 側のバージョンアップで項目が追加され得るため、すべてを専用型に固定化すると SDK の追従コストが上がる
  - 既知項目だけ型で公開し、未知項目は raw で残す併存案を採るかどうかの判断が必要
- `notify` の **単一型 vs event_type ごとの派生型**
  - `notify` は `event_type`（`connection.created` / `connection.updated` / `connection.destroyed` / `network.status` / `spotlight.*` など）ごとに構造差が大きい
  - 単一型にすると optional が増え API 契約が弱くなる
  - 派生型にすると公開型数が増え、Sora 側の event_type 追加に追従する義務が発生する
- **公開 API 契約の線引き**
  - どのフィールドを public API 契約として保証するかを決める必要がある
  - たとえば `event_type` / `connection_id` / `ignore_disconnect_websocket` のような利用頻度の高い項目に限定するか、全項目を公開するか

これらは API 設計の根幹に関わる判断であり、着手は番号順（AGENTS.md 方針）よりも方針決定後に回す。方針が決まり次第、pending から戻して実装する。

## 解決方法

1. 併存方針と型階層を決める
2. 既存イベント型を専用型へ置き換える
3. example と `CHANGES.md` を更新して、方針決定後に pending を解除する
