import 'dart:convert';

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:puro/src/config.dart';
import 'package:puro/src/env/flutter_tool.dart';
import 'package:puro/src/logger.dart';
import 'package:puro/src/provider.dart';
import 'package:puro/src/version.dart';
import 'package:test/test.dart';

/// Builds a scope with an environment rooted in an empty in-memory filesystem.
EnvConfig _createEnvironment() {
  final fileSystem = MemoryFileSystem();
  final puroRoot = fileSystem.directory('/.puro')..createSync(recursive: true);
  final config = PuroConfig(
    fileSystem: fileSystem,
    gitExecutable: fileSystem.file('/usr/bin/git'),
    globalPrefsJsonFile: puroRoot.childFile('prefs.json'),
    puroRoot: puroRoot,
    legacyPubCacheDir: puroRoot.childDirectory('pub_cache'),
    legacyPubCache: false,
    homeDir: fileSystem.directory('/home'),
    projectDir: null,
    parentProjectDir: null,
    flutterGitUrl: '',
    engineGitUrl: '',
    dartSdkGitUrl: '',
    releasesJsonUrl: Uri.parse('https://example.com/releases.json'),
    flutterStorageBaseUrl: Uri.parse('https://example.com'),
    environmentOverride: null,
    puroBuildsUrl: Uri.parse('https://example.com/builds'),
    buildTarget: PuroBuildTarget.linuxX64,
    enableShims: false,
    shouldInstall: false,
    shouldSkipCacheSync: true,
  );
  final environment = EnvConfig(
    parentConfig: config,
    envDir: config.envsDir.childDirectory('stable'),
  );
  environment.flutter.cacheDir.createSync(recursive: true);
  return environment;
}

Scope _createScope() {
  final scope = RootScope();
  scope.add(PuroLogger.provider, PuroLogger());
  return scope;
}

void _writeVersionJson(EnvConfig environment, Object? contents) {
  environment.flutter.cache.versionJsonFile.writeAsStringSync(
    contents is String ? contents : jsonEncode(contents),
  );
}

void main() {
  group('fixLegacyVersionFile (Issue #2)', () {
    late Scope scope;
    late EnvConfig environment;
    late File versionJsonFile;
    late File legacyVersionFile;

    setUp(() {
      scope = _createScope();
      environment = _createEnvironment();
      versionJsonFile = environment.flutter.cache.versionJsonFile;
      legacyVersionFile = environment.flutter.legacyVersionFile;
    });

    test('writes legacy version file without deleting JSON', () async {
      _writeVersionJson(environment, {
        'frameworkVersion': '3.35.7',
        'flutterVersion': '3.35.7',
      });

      await fixLegacyVersionFile(scope: scope, environment: environment);

      expect(versionJsonFile.existsSync(), isTrue);
      expect(legacyVersionFile.readAsStringSync().trim(), '3.35.7');
    });

    test('overwrites stale legacy version file', () async {
      legacyVersionFile.writeAsStringSync('3.35.7\n');
      _writeVersionJson(environment, {'frameworkVersion': '3.38.1'});

      await fixLegacyVersionFile(scope: scope, environment: environment);

      expect(legacyVersionFile.readAsStringSync().trim(), '3.38.1');
    });

    test('leaves up-to-date legacy version file alone', () async {
      legacyVersionFile.writeAsStringSync('3.38.1');
      _writeVersionJson(environment, {'frameworkVersion': '3.38.1'});
      final modified = legacyVersionFile.lastModifiedSync();

      await fixLegacyVersionFile(scope: scope, environment: environment);

      expect(legacyVersionFile.lastModifiedSync(), modified);
    });

    test('does nothing when JSON is missing', () async {
      await fixLegacyVersionFile(scope: scope, environment: environment);

      expect(versionJsonFile.existsSync(), isFalse);
      expect(legacyVersionFile.existsSync(), isFalse);
    });

    test('deletes JSON if it has no frameworkVersion', () async {
      _writeVersionJson(environment, {'channel': 'stable'});

      await fixLegacyVersionFile(scope: scope, environment: environment);

      expect(versionJsonFile.existsSync(), isFalse);
      expect(legacyVersionFile.existsSync(), isFalse);
    });

    test('deletes JSON if it is not valid JSON', () async {
      _writeVersionJson(environment, 'not json');

      await fixLegacyVersionFile(scope: scope, environment: environment);

      expect(versionJsonFile.existsSync(), isFalse);
    });
  });

  group('ensureFlutterVersionJson (Issue #2)', () {
    late Scope scope;
    late EnvConfig environment;
    late File versionJsonFile;

    setUp(() {
      scope = _createScope();
      environment = _createEnvironment();
      versionJsonFile = environment.flutter.cache.versionJsonFile;
    });

    test(
      'fast-path returns immediately without spawning command when version JSON exists',
      () async {
        _writeVersionJson(environment, {'frameworkVersion': '3.35.7'});

        await ensureFlutterVersionJson(scope: scope, environment: environment);

        expect(versionJsonFile.existsSync(), isTrue);
      },
    );
  });
}
