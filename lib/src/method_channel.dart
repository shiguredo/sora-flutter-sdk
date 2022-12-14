import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'client.dart';
import 'platform_interface.dart';

/// An implementation of [SoraFlutterSdkPlatform] that uses method channels.
class MethodChannelSoraFlutterSdk extends SoraFlutterSdkPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('sora_flutter_sdk');

  @override
  Future<SoraClient> createSoraClient(SoraClientConfig config) async {
    final req = {
      'config': json.encode(config.toJson()),
    };
    final resp = await methodChannel.invokeMethod('createSoraClient', req);
    final client = SoraClient(
        resp, _connectSoraClient, _disposeSoraClient, _destroySoraClient);
    return client;
  }

  Future<void> _connectSoraClient(SoraClient client) async {
    await methodChannel.invokeMethod('connectSoraClient', {
      'client_id': client.clientId,
    });
  }

  Future<void> _disposeSoraClient(SoraClient client) async {
    await methodChannel.invokeMethod('disposeSoraClient', {
      'client_id': client.clientId,
    });
  }

  Future<void> _destroySoraClient(SoraClient client) async {
    await methodChannel.invokeMethod('destroySoraClient', {
      'client_id': client.clientId,
    });
  }

  @override
  Future<bool> sendDataChannel({
    required SoraClient client,
    required String label,
    required Uint8List data,
  }) async {
    return await methodChannel.invokeMethod('sendDataChannel', {
      'client_id': client.clientId,
      'label': label,
      'data': data,
    });
  }
}
