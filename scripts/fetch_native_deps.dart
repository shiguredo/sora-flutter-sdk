#!/usr/bin/env dart
// Android / Linux / Windows 向けのネイティブ依存関係（libwebrtc-c / webrtc）をダウンロード・展開・インストールするスクリプト。
// 引数でプラットフォーム名（android_arm64 / linux_ubuntu_22_04_x86_64 等）を受け取る。
//
// native_deps.json に各依存のバージョン、ダウンロード URL、アーカイブの SHA256 が定義されている。
// 取得済みの依存情報は .state.json に保存され、バージョン・アーカイブ名に変更がない場合は再取得をスキップする。
// インストール先は third_party/libwebrtc-c/ 。

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

final scriptDir = File(Platform.script.toFilePath()).parent;
final rootDir = scriptDir.parent;
// プラットフォームごとのバージョン指定ファイルパス
final manifestPath = File(p.join(scriptDir.path, 'native_deps.json'));
// インストール先ディレクトリ
final installDir = Directory(
  p.join(rootDir.path, 'third_party', 'libwebrtc-c'),
);
// インストール済みバージョンの管理ファイルパス
final statePath = File(p.join(installDir.path, '.state.json'));

const dependencyNames = ['libwebrtc_c', 'webrtc'];

// プラットフォームごとのディレクトリ・ファイル構成
const platformConfig = {
  'android_arm64': {
    'build_dir': 'build-android_arm64',
    'extract_paths': ['build-android_arm64'],
    'required_paths': [
      'include/webrtc_c.h',
      'build-android_arm64/libwebrtc-c.a',
      'build-android_arm64/_deps/webrtc/include',
      'build-android_arm64/_deps/webrtc/lib/arm64-v8a/libwebrtc.a',
      'build-android_arm64/_deps/webrtc/jar/webrtc.jar',
    ],
  },
  'linux_ubuntu_22_04_x86_64': {
    'build_dir': 'build-linux_ubuntu_22_04_x86_64',
    'extract_paths': ['build-linux_ubuntu_22_04_x86_64'],
    'required_paths': [
      'include/webrtc_c.h',
      'build-linux_ubuntu_22_04_x86_64/libwebrtc-c.a',
      'build-linux_ubuntu_22_04_x86_64/_deps/webrtc/include',
      'build-linux_ubuntu_22_04_x86_64/_deps/webrtc/lib/libwebrtc.a',
    ],
  },
  'linux_ubuntu_24_04_x86_64': {
    'build_dir': 'build-linux_ubuntu_24_04_x86_64',
    'extract_paths': ['build-linux_ubuntu_24_04_x86_64'],
    'required_paths': [
      'include/webrtc_c.h',
      'build-linux_ubuntu_24_04_x86_64/libwebrtc-c.a',
      'build-linux_ubuntu_24_04_x86_64/_deps/webrtc/include',
      'build-linux_ubuntu_24_04_x86_64/_deps/webrtc/lib/libwebrtc.a',
    ],
  },
  'windows_x86_64': {
    'build_dir': 'build-windows_x86_64',
    'extract_paths': ['build-windows_x86_64'],
    'required_paths': [
      'include/webrtc_c.h',
      'build-windows_x86_64/libwebrtc-c.lib',
      'build-windows_x86_64/_deps/webrtc/include',
      'build-windows_x86_64/_deps/webrtc/lib/webrtc.lib',
    ],
  },
};

// パス構築ヘルパー
File childFile(Directory dir, String name) => File(p.join(dir.path, name));
Directory childDir(Directory dir, String name) =>
    Directory(p.join(dir.path, name));

/// スクリプトをエラーメッセージ付きで異常終了させる。
void failWith(String message) {
  stderr.writeln(message);
  exit(1);
}

/// JSON ファイルを読み取り、Map として返す。
/// ファイルが見つからない場合や JSON のパースに失敗した場合は異常終了する。
Map<String, dynamic> loadJson(File path) {
  try {
    final content = path.readAsStringSync();
    return jsonDecode(content) as Map<String, dynamic>;
  } on FileSystemException {
    failWith('File not found: ${path.path}');
  } on FormatException catch (e) {
    failWith('Failed to parse JSON: ${path.path}: $e');
  }
  throw StateError('unreachable');
}

/// native_deps.json を読み取り、各依存の version / base_url / archives を抽出する。
Map<String, dynamic> loadManifest() {
  final manifest = loadJson(manifestPath);
  final parsed = <String, dynamic>{};

  for (final name in dependencyNames) {
    final dependency = manifest[name];
    if (dependency is! Map<String, dynamic>) {
      failWith('$name is not set in ${manifestPath.path}');
    }
    final dep = dependency as Map<String, dynamic>;

    final version = (dep['version'] as String).trim();
    final baseUrl = (dep['base_url'] as String).trim();
    final archives = dep['archives'];

    if (version.isEmpty) {
      failWith('version is not set for $name in ${manifestPath.path}');
    }
    if (baseUrl.isEmpty) {
      failWith('base_url is not set for $name in ${manifestPath.path}');
    }
    if (archives is! Map<String, dynamic>) {
      failWith('archives is not set for $name in ${manifestPath.path}');
    }

    parsed[name] = {
      'version': version,
      'base_url': baseUrl,
      'archives': archives,
    };
  }

  return parsed;
}

/// .state.json を読み取り、前回取得時の依存状態を返す。
/// ファイルが存在しない場合は空の state を生成する。
Map<String, dynamic> loadState() {
  Map<String, dynamic> state;
  if (statePath.existsSync()) {
    state = loadJson(statePath);
  } else {
    state = <String, dynamic>{'dependencies': <String, dynamic>{}};
  }

  final dependencies =
      state['dependencies'] as Map<String, dynamic>? ?? <String, dynamic>{};
  state['dependencies'] = dependencies;

  for (final name in dependencyNames) {
    final depState =
        dependencies[name] as Map<String, dynamic>? ?? <String, dynamic>{};
    dependencies[name] = depState;

    final archives =
        depState['archives'] as Map<String, dynamic>? ?? <String, dynamic>{};
    depState['archives'] = archives;

    final versions =
        depState['versions'] as Map<String, dynamic>? ?? <String, dynamic>{};
    depState['versions'] = versions;
  }

  return state;
}

/// アーカイブのダウンロード URL を組み立てる。
String archiveUrl(String baseUrl, String version, String fileName) {
  return '$baseUrl/$version/$fileName';
}

/// アーカイブの SHA256 ハッシュが manifest に設定されていることを確認し、値を返す。
/// 未設定の場合は異常終了する。
String ensureSha256(
  String dependencyName,
  String platform,
  Map<String, dynamic> archive,
) {
  final sha256 = (archive['sha256'] as String).trim();
  if (sha256.isEmpty) {
    failWith(
      'sha256 is not set for $dependencyName.$platform in ${manifestPath.path}',
    );
  }
  return sha256;
}

/// プラットフォームの required_paths に指定された全パスが存在するか確認する。
bool requiredPathsExist(String platform) {
  final config = platformConfig[platform]! as Map<String, dynamic>;
  final requiredPaths = config['required_paths'] as List<dynamic>;
  return requiredPaths.every((relPath) {
    final fullPath = p.join(installDir.path, relPath as String);
    return FileSystemEntity.isFileSync(fullPath) ||
        FileSystemEntity.isDirectorySync(fullPath);
  });
}

/// 前回取得時から依存のバージョン・アーカイブ名に変更がなく、
/// かつ required_paths がすべて存在する場合に true を返す。
/// 取得をスキップできるかの判定に使う。
bool skipFetch(
  String platform,
  Map<String, dynamic> manifest,
  Map<String, dynamic> state,
) {
  var allDependenciesMatch = true;
  final dependencies = state['dependencies'] as Map<String, dynamic>;

  for (final name in dependencyNames) {
    final depManifest = manifest[name] as Map<String, dynamic>;
    final depState = dependencies[name] as Map<String, dynamic>;
    final archives = depManifest['archives'] as Map<String, dynamic>;
    final archive = archives[platform] as Map<String, dynamic>?;

    if (archive == null) {
      failWith(
        'archive is not set for $name.$platform in ${manifestPath.path}',
      );
    }

    final versions = depState['versions'] as Map<String, dynamic>;
    if (versions[platform] != depManifest['version']) {
      allDependenciesMatch = false;
      break;
    }

    final savedArchives = depState['archives'] as Map<String, dynamic>;
    if (savedArchives[platform] != archive!['file']) {
      allDependenciesMatch = false;
      break;
    }
  }

  return allDependenciesMatch && requiredPathsExist(platform);
}

/// 指定プラットフォームの extract_paths に該当するディレクトリを削除する。
/// 依存のバージョンが変更された際に、古いビルド成果物を除去してから
/// 新バージョンを取得するための準備として呼ばれる。
void cleanPlatform(String platform) {
  final config = platformConfig[platform]! as Map<String, dynamic>;
  final extractPaths = config['extract_paths'] as List<dynamic>;
  for (final p in extractPaths) {
    final dir = childDir(installDir, p as String);
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  }
}

/// URL からファイルをダウンロードし、指定のパスへ保存する。
Future<void> downloadArchiveAsync(String url, File destination) async {
  try {
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();

    if (response.statusCode != HttpStatus.ok) {
      failWith('Failed to download $url: HTTP ${response.statusCode}');
    }

    final sink = destination.openWrite();
    await response.pipe(sink);
  } on SocketException catch (e) {
    failWith('Failed to resolve host for $url: $e');
  } on HttpException catch (e) {
    failWith('Failed to download $url: $e');
  } catch (e) {
    failWith('Failed to download $url: $e');
  }
}

/// ダウンロードしたアーカイブの SHA256 ハッシュを検証する。
/// 不一致の場合は異常終了する。
Future<void> verifySha256Async(File archivePath, String expectedSha256) async {
  final bytes = await archivePath.readAsBytes();
  final digest = sha256.convert(bytes);
  final actualSha256 = digest.toString();

  if (actualSha256 != expectedSha256) {
    failWith(
      'SHA256 mismatch for ${archivePath.path}: '
      'expected=$expectedSha256 actual=$actualSha256',
    );
  }
}

/// アーカイブを展開し、展開先ディレクトリを返す。
/// archive パッケージの extractFileToDisk で .tar.gz / .zip 両方を処理する。
Future<Directory> extractArchive(File archivePath) async {
  final extractDir = childDir(archivePath.parent, 'extracted');
  extractDir.createSync(recursive: true);

  try {
    await extractFileToDisk(archivePath.path, extractDir.path);
  } catch (e) {
    // 展開に失敗した場合は不完全な展開結果を削除して終了する
    if (extractDir.existsSync()) {
      extractDir.deleteSync(recursive: true);
    }
    failWith('Failed to extract ${archivePath.path}: $e');
  }

  return extractDir;
}

/// パス（ファイルまたはディレクトリ）を再帰的にコピーする。シンボリックリンクも保持。
void copyPathIfExists(Directory source, Directory dest) {
  if (!source.existsSync()) return;

  if (dest.existsSync()) {
    dest.deleteSync(recursive: true);
  }

  dest.parent.createSync(recursive: true);
  _copyDirectoryRecursive(source, dest);
}

/// ディレクトリを再帰的にコピーする internal 処理。
void _copyDirectoryRecursive(Directory source, Directory dest) {
  dest.createSync(recursive: true);

  for (final entity in source.listSync(recursive: false)) {
    final name = p.basename(entity.path);
    final newDest = childDir(dest, name);

    if (entity is Link) {
      final target = entity.targetSync();
      final link = Link(newDest.path);
      link.createSync(target);
    } else if (entity is Directory) {
      _copyDirectoryRecursive(entity, newDest);
    } else if (entity is File) {
      final destFile = childFile(dest, name);
      destFile.writeAsBytesSync(entity.readAsBytesSync());
    }
  }
}

/// 展開されたディレクトリから libwebrtc-c の静的ライブラリとヘッダを
/// インストール先へコピーする。
Future<void> installLibwebrtcC(String platform, Directory extractedDir) async {
  final config = platformConfig[platform]! as Map<String, dynamic>;
  final buildDir = childDir(installDir, config['build_dir'] as String);
  buildDir.createSync(recursive: true);

  // Android/Linux は libwebrtc_c.a / libwebrtc-c.a、Windows は webrtc_c.lib
  final staticLibraryCandidates = [
    childDir(childDir(extractedDir, 'lib'), 'libwebrtc_c.a'),
    childDir(childDir(extractedDir, 'lib'), 'libwebrtc-c.a'),
    childDir(childDir(extractedDir, 'lib'), 'webrtc_c.lib'),
  ].map((d) => File(d.path)).toList();

  File? staticLibraryPath;
  for (final path in staticLibraryCandidates) {
    if (path.existsSync()) {
      staticLibraryPath = path;
      break;
    }
  }

  if (staticLibraryPath == null) {
    failWith('libwebrtc_c static library is missing for $platform');
  }

  // ソースの拡張子が .lib の場合はコピー先も .lib にする
  final libPath = staticLibraryPath!;
  final sourceExtension = p.extension(libPath.path);
  final destFileName = sourceExtension == '.lib'
      ? 'libwebrtc-c.lib'
      : 'libwebrtc-c.a';
  final destinationPath = childFile(buildDir, destFileName);
  libPath.copySync(destinationPath.path);
  final includeCandidates = [
    childDir(extractedDir, 'include'),
    childDir(childDir(extractedDir, 'libwebrtc-c'), 'include'),
  ];

  Directory? includePath;
  for (final path in includeCandidates) {
    if (path.existsSync()) {
      includePath = path;
      break;
    }
  }

  if (includePath != null) {
    copyPathIfExists(includePath, childDir(installDir, 'include'));
  }
}

/// 展開されたディレクトリから webrtc のヘッダ・ライブラリを
/// インストール先へコピーする。
Future<void> installWebrtc(String platform, Directory extractedDir) async {
  final config = platformConfig[platform]! as Map<String, dynamic>;
  final buildDir = childDir(installDir, config['build_dir'] as String);
  final depsDir = childDir(buildDir, '_deps');
  depsDir.createSync(recursive: true);

  Directory? webrtcPath;
  final candidates = [childDir(extractedDir, 'webrtc'), extractedDir];
  for (final path in candidates) {
    if (childDir(path, 'include').existsSync()) {
      webrtcPath = path;
      break;
    }
  }

  // 直接マッチしない場合は再帰的に include/ を探す
  if (webrtcPath == null) {
    for (final e in extractedDir.listSync(recursive: true)) {
      if (e is Directory && p.basename(e.path) == 'include') {
        webrtcPath = e.parent;
        break;
      }
    }
  }

  if (webrtcPath == null) {
    failWith('webrtc directory is missing for $platform');
  }

  copyPathIfExists(webrtcPath!, childDir(depsDir, 'webrtc'));
}

/// 依存名に応じてインストール処理を振り分ける。
Future<void> installDependency(
  String name,
  String platform,
  Directory extractedDir,
) async {
  if (name == 'libwebrtc_c') {
    await installLibwebrtcC(platform, extractedDir);
  } else if (name == 'webrtc') {
    await installWebrtc(platform, extractedDir);
  } else {
    failWith('Unsupported dependency: $name');
  }
}

/// インストール後に required_paths がすべて存在することを検証する。
void validateRequiredPaths(String platform) {
  final config = platformConfig[platform]! as Map<String, dynamic>;
  final requiredPaths = config['required_paths'] as List<dynamic>;

  final missingPaths = <String>[];
  for (final relPath in requiredPaths) {
    final fullPath = p.join(installDir.path, relPath as String);
    if (!FileSystemEntity.isFileSync(fullPath) &&
        !FileSystemEntity.isDirectorySync(fullPath)) {
      missingPaths.add(relPath);
    }
  }

  if (missingPaths.isNotEmpty) {
    failWith(
      'Missing required paths for $platform: ${missingPaths.join(', ')}',
    );
  }
}

/// 依存状態を .state.json に保存する。
void saveState(Map<String, dynamic> state) {
  installDir.createSync(recursive: true);
  statePath.writeAsStringSync('${jsonEncode(state)}\n');
}

/// 指定プラットフォームの単一依存をダウンロード・検証・展開・インストールする。
/// 完了後、state にバージョンとアーカイブ名を記録する。
Future<void> fetchDependency(
  String name,
  String platform,
  Map<String, dynamic> manifest,
  Map<String, dynamic> state,
) async {
  final depManifest = manifest[name] as Map<String, dynamic>;
  final archives = depManifest['archives'] as Map<String, dynamic>;
  final archive = archives[platform] as Map<String, dynamic>?;

  if (archive == null) {
    failWith('archive is not set for $name.$platform in ${manifestPath.path}');
  }

  final fileName = (archive!['file'] as String).trim();
  if (fileName.isEmpty) {
    failWith('file is not set for $name.$platform in ${manifestPath.path}');
  }

  final expectedSha256 = ensureSha256(name, platform, archive);
  final url = archiveUrl(
    depManifest['base_url'] as String,
    depManifest['version'] as String,
    fileName,
  );

  final tmpDir = Directory.systemTemp.createTempSync(
    'sora_sdk_native_deps_${name}_${platform}_',
  );

  try {
    final archivePath = childFile(tmpDir, fileName);
    stderr.writeln(
      'Downloading native dependency for $name.$platform from $url',
    );

    await downloadArchiveAsync(url, archivePath);
    await verifySha256Async(archivePath, expectedSha256);
    final extractedDir = await extractArchive(archivePath);
    await installDependency(name, platform, extractedDir);
  } finally {
    tmpDir.deleteSync(recursive: true);
  }

  final dependencies = state['dependencies'] as Map<String, dynamic>;
  final depState = dependencies[name] as Map<String, dynamic>;
  final versions = depState['versions'] as Map<String, dynamic>;
  final savedArchives = depState['archives'] as Map<String, dynamic>;

  versions[platform] = depManifest['version'];
  savedArchives[platform] = fileName;
}

/// 引数で指定されたプラットフォームが platformConfig に存在するか検証する。
/// 未サポートのプラットフォームが指定された場合は異常終了する。
void validatePlatform(String platform) {
  if (!platformConfig.containsKey(platform)) {
    final supported = platformConfig.keys.toList()..sort();
    failWith(
      'Unsupported platform: $platform. Supported platforms: ${supported.join(', ')}',
    );
  }
}

/// ネイティブ依存ファイルダウンロードのメイン処理。
Future<int> main(List<String> args) async {
  final platforms = args;
  if (platforms.isEmpty) {
    final supported = platformConfig.keys.toList()..sort();
    failWith(
      'Usage: dart run scripts/fetch_native_deps.dart <platform> [${supported.join(', ')}]',
    );
  }

  for (final platform in platforms) {
    validatePlatform(platform);
  }

  final manifest = loadManifest();
  final state = loadState();
  installDir.createSync(recursive: true);

  // プラットフォーム毎に取得する
  for (final platform in platforms) {
    if (skipFetch(platform, manifest, state)) {
      stderr.writeln('Native dependency is up to date for $platform');
      continue;
    }

    // 古いファイルが存在する可能性があるので掃除する
    cleanPlatform(platform);

    for (final name in dependencyNames) {
      await fetchDependency(name, platform, manifest, state);
    }

    validateRequiredPaths(platform);
    saveState(state);
  }

  return 0;
}
