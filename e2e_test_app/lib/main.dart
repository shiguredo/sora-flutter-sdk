// E2E 用の最小アプリ。integration_test がエンジンとプラグインを載せるためのエントリのみ。
import 'package:flutter/material.dart';

void main() {
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: SizedBox.shrink(),
      ),
    ),
  );
}
