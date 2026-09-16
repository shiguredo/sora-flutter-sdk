# 可変参照を保持するデータクラスの深い immutable 化を保留する
- Priority: Low
- Created: 2026-04-29
- Model: GPT-5.4
- Polished: 2026-06-05

## 目的

`SoraSignalingEvent`、`SoraDataChannelMessage`、`ExternalVideoFrame`、`SoraConnectionConfig` など、`List` / `Map` / `Uint8List` / `Object?` のような可変参照を直接保持する公開データクラスについて、deep immutable を保証するための defensive copy や unmodifiable view 導入は、現時点では対応しない。

## 優先度根拠

- `@immutable` を安全に付与するには、コンストラクタ入口での defensive copy や、公開 getter での `UnmodifiableListView` / `Map.unmodifiable` などの追加が必要になる
- 対象クラスは signaling payload、DataChannel payload、外部映像フレームなどパフォーマンスと所有権の整理が難しい領域にまたがる
- shallow immutable の明示よりも、コピー戦略、所有権、API 契約の再設計コストが大きい
- 現時点の過去の immutable 化 issue (P1) の主目的は、単純な値オブジェクトへの `@immutable` 付与と `SoraConnectionConfig.timeoutOptions` の整理であり、deep immutable 化まで広げるとスコープが過大になる

## 現状

- 一部公開データクラスは `final` フィールドのみでも、保持している参照先が可変なので `@immutable` を付けられない
- 利用者が渡した `List` / `Map` / `Uint8List` を SDK がそのまま保持する契約になっている箇所がある
- deep immutable 化を安易に入れると、コピーコスト増加や payload 取り回しの後方互換影響が出る

## 設計方針

1. deep immutable 化の対象クラスを洗い出す
2. 各クラスで defensive copy が妥当か、所有権移譲前提の API が妥当かを整理する
3. signaling payload、DataChannel payload、外部映像フレームで性能影響を見積もる
4. 必要なら breaking change として API 契約を再定義する

## 完了条件

- deep immutable 化の対象クラス一覧が確定している
- 各クラスで defensive copy / unmodifiable view / 所有権移譲のどれを採るか方針が定まっている
- 性能影響と後方互換影響が整理されている
- `@immutable` を付ける範囲と付けない範囲の説明が issue と変更履歴で一貫している

## pending 理由

deep immutable 化は、単純な `@immutable` 付与より設計・性能・後方互換への影響が大きい。現時点では費用対効果が薄く、P1 の目的である単純な値オブジェクト整理から外れるため、設計判断待ちの pending issue として分離する。

## 解決方法

1. deep immutable 化の対象を限定する
2. defensive copy と所有権移譲の方針を決める
3. 必要な範囲だけ breaking change として実装する
