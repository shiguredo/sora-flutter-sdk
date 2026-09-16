// ignore_for_file: public_member_api_docs
import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

/// SDK 内部で共有する MethodChannel です。
@internal
const MethodChannel soraMethodChannel = MethodChannel('sora_sdk/method');
