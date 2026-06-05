// ignore_for_file: public_member_api_docs
// libwebrtc-c のメモリ管理ユーティリティ

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'bindings.dart';

// `std_string_unique*` を Dart `String` に変換して解放する。
//
// C++ 側で返された unique ownership の文字列を Dart に移し替える補助関数。
// 取得後は必ず `std_string_unique_delete` まで完了させ、呼び出し元へ
// ネイティブ所有権を残さない。
String stdStringToDart(LibWebrtcC lib, Pointer<StdStringUnique> value) {
  if (value == nullptr) {
    return '';
  }
  final str = lib.stdStringUniqueGet(value);
  final cstr = lib.stdStringCStr(str);
  final result = cstr == nullptr ? '' : cstr.cast<Utf8>().toDartString();
  lib.stdStringUniqueDelete(value);
  return result;
}

// `RTCError_unique` からエラーメッセージを取り出して解放する。
//
// WebRTC の API は成功時にも `RTCError_unique` を返すことがあるため、
// まず `rtcErrorOk` で成功か失敗かを判定する。失敗時のみメッセージを
// Dart 文字列へ変換し、最後に `RTCError_unique` 自体も破棄する。
String? rtcErrorMessage(LibWebrtcC lib, Pointer<WebrtcRTCErrorUnique> error) {
  if (error == nullptr) {
    return null;
  }
  final err = lib.rtcErrorUniqueGet(error);
  if (lib.rtcErrorOk(err) != 0) {
    lib.rtcErrorUniqueDelete(error);
    return null;
  }
  final messagePtr = calloc<Pointer<Char>>();
  final lenPtr = calloc<Size>();
  lib.rtcErrorMessage(err, messagePtr, lenPtr);
  final message = messagePtr.value;
  final len = lenPtr.value;
  String result;
  if (message != nullptr && len > 0) {
    result = message.cast<Utf8>().toDartString(length: len);
  } else {
    result = '';
  }
  calloc.free(messagePtr);
  calloc.free(lenPtr);
  lib.rtcErrorUniqueDelete(error);
  return result;
}
