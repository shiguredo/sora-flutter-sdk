import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sora_flutter_sdk/sora_flutter_sdk.dart';

import 'environment.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  SoraClient? _soraClient;
  var _isConnected = false;

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  Future<void> initPlatformState() async {
    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) {
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Builder(builder: _buildMain),
    );
  }

  Widget _buildMain(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    return Center(
      child: Column(
        children: [
          SizedBox(
            height: screenSize.height * 0.8,
            child:
            SingleChildScrollView(
              child:
              Center(
                child: _buildRenderers(),
              ),
            ),
          ),
          SizedBox(
            height: screenSize.height * 0.2,
            child:
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: () async {
                          await _connect();
                        },
                        child: const Text('接続する'),
                      ),
                      const SizedBox(width: 20),
                      ElevatedButton(
                        onPressed: () async {
                          await _disconnect();
                        },
                        child: const Text('切断する'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRenderers() {
    print('build renderers');
    var renderers = List<SoraRenderer>.empty();
    if (_soraClient != null) {
      renderers = _soraClient!.tracks
          .map((track) => SoraRenderer(
        width: 320,
        height: 240,
        track: track,
      ))
          .toList();
    }

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      children: renderers,
    );
  }

  Future<void> _connect() async {
    if (_isConnected) {
      return;
    }
    if (_soraClient != null) {
      dispose();
    }

    final config = SoraClientConfig(
      signalingUrls: Environment.urlCandidates,
      channelId: Environment.channelId,
      role: SoraRole.sendrecv,
    );

    config.metadata = Environment.signalingMetadata;

    final soraClient = await SoraClient.create(config)
      ..onDisconnect = (String errorCode, String message) {
        print("OnDisconnect: ec=$errorCode message=$message");
      }
      ..onSetOffer = (String offer) {
        print("OnSetOffer: $offer");
      }
      ..onNotify = (String text) {
        print("OnNotify: $text");
      }
      ..onAddTrack = (SoraVideoTrack track) {
        setState(() {/* soraClient.tracks の数が変動したので描画し直す */});
      }
      ..onRemoveTrack = (SoraVideoTrack track) {
        setState(() {/* soraClient.tracks の数が変動したので描画し直す */});
      };

    try {
      await soraClient.connect();

      setState(() {
        _soraClient = soraClient;
        _isConnected = true;
      });
    } on Exception catch (e) {
      print('connect failed => $e');
    }
  }

  Future<void> _disconnect() async {
    if (!_isConnected && _soraClient == null) {
      return;
    }
    print('disconnect');

    try {
      await _soraClient?.dispose();
    } on Exception catch (e) {
      print('dispose failed => $e');
    }

    setState(() {
      _soraClient = null;
      _isConnected = false;
    });
  }
}
