import 'dart:convert';
import 'dart:io';

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:http/http.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:puro/src/command.dart';
import 'package:puro/src/commands/puro_upgrade.dart';
import 'package:puro/src/config.dart';
import 'package:puro/src/http.dart';
import 'package:puro/src/logger.dart';
import 'package:puro/src/provider.dart';
import 'package:puro/src/terminal.dart';
import 'package:puro/src/version.dart';
import 'package:test/test.dart';

class MockHttpClient extends BaseClient {
  MockHttpClient([this.handler]);

  final Future<Response> Function(BaseRequest request)? handler;
  final List<Uri> requestedUris = [];

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    requestedUris.add(request.url);
    if (handler != null) {
      final response = await handler!(request);
      return StreamedResponse(
        Stream.value(response.bodyBytes),
        response.statusCode,
        headers: response.headers,
      );
    }
    return StreamedResponse(Stream.value(utf8.encode('2.0.0')), 200);
  }
}

class TestPuroCommandRunner extends PuroCommandRunner {
  TestPuroCommandRunner(Scope scope)
    : super('puro', 'Puro test runner', scope: scope, isJson: false) {
    argParser.addFlag('version', negatable: false);
  }

  int? exitCode;

  @override
  Future<Never> exitPuro(int code) async {
    exitCode = code;
    throw PuroExitException(code);
  }
}

class PuroExitException implements Exception {
  PuroExitException(this.code);
  final int code;
}

Scope createTestScope({
  required FileSystem fileSystem,
  String? executablePathOverride,
  bool? isForkOverride,
  String? puroVersionDefineOverride,
  PuroVersion? version,
  MockHttpClient? httpClient,
  Uri? puroBuildsUrl,
}) {
  final scope = RootScope();
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
    puroBuildsUrl: puroBuildsUrl ?? Uri.parse('https://puro.dev/builds'),
    buildTarget: PuroBuildTarget.linuxX64,
    enableShims: false,
    shouldInstall: false,
    shouldSkipCacheSync: true,
  );

  scope.add(PuroConfig.provider, config);
  scope.add(globalPrefsJsonFileProvider, config.globalPrefsJsonFile);
  scope.add(isFirstRunProvider, false);
  scope.add(PuroLogger.provider, PuroLogger());
  scope.add(Terminal.provider, Terminal(stdout: stderr));
  scope.add(clientProvider, httpClient ?? MockHttpClient());
  if (executablePathOverride != null) {
    scope.add(
      PuroVersion.executablePathOverrideProvider,
      executablePathOverride,
    );
  }
  if (isForkOverride != null) {
    scope.add(PuroVersion.isForkOverrideProvider, isForkOverride);
  }
  if (puroVersionDefineOverride != null) {
    scope.add(
      PuroVersion.puroVersionDefineOverrideProvider,
      puroVersionDefineOverride,
    );
  }
  if (version != null) {
    scope.add(PuroVersion.provider, Future.value(version));
  }
  return scope;
}

void main() {
  group(
    'dart install app-bundle version resolution & upgrade protection (Issue #13)',
    () {
      test(
        'Scenario a: Git app-bundle with pubspec.lock + pubspec.yaml -> appBundle, 2.0.0-fork+315c01e',
        () async {
          final fs = MemoryFileSystem();
          const exePath =
              '/Dart/install/app-bundles/puro/git/315c01edeba18abb0e7a766d5bf0f352f6d543b5/bundle/bin/puro';
          fs.file(exePath).createSync(recursive: true);

          final bundleDir = fs.file(exePath).parent.parent.parent;
          bundleDir.childFile('pubspec.yaml').writeAsStringSync('''
name: puro
version: 2.0.0
''');
          bundleDir.childFile('pubspec.lock').writeAsStringSync('''
packages:
  puro:
    version: "2.0.0"
    source: git
    description:
      resolved-ref: 315c01edeba18abb0e7a766d5bf0f352f6d543b5
''');

          final scope = createTestScope(
            fileSystem: fs,
            executablePathOverride: exePath,
            isForkOverride: true,
          );

          final puroVersion = await PuroVersion.of(scope);

          expect(puroVersion.type, equals(PuroInstallationType.appBundle));
          expect(puroVersion.semver.toString(), equals('2.0.0-fork+315c01e'));
        },
      );

      test(
        'Scenario b: Git app-bundle with only pubspec.yaml -> extracts commit hash from directory path, 2.0.0-fork+315c01e',
        () async {
          final fs = MemoryFileSystem();
          const exePath =
              '/Dart/install/app-bundles/puro/git/315c01edeba18abb0e7a766d5bf0f352f6d543b5/bundle/bin/puro';
          fs.file(exePath).createSync(recursive: true);

          final bundleDir = fs.file(exePath).parent.parent.parent;
          bundleDir.childFile('pubspec.yaml').writeAsStringSync('''
name: puro
version: 2.0.0
''');

          final scope = createTestScope(
            fileSystem: fs,
            executablePathOverride: exePath,
            isForkOverride: true,
          );

          final puroVersion = await PuroVersion.of(scope);

          expect(puroVersion.type, equals(PuroInstallationType.appBundle));
          expect(puroVersion.semver.toString(), equals('2.0.0-fork+315c01e'));
        },
      );

      test(
        'Scenario c: Hosted app-bundle with pubspec.yaml -> resolves 2.0.0-fork',
        () async {
          final fs = MemoryFileSystem();
          const exePath =
              '/Dart/install/app-bundles/puro/hosted/2.0.0/bundle/bin/puro';
          fs.file(exePath).createSync(recursive: true);

          final bundleDir = fs.file(exePath).parent.parent.parent;
          bundleDir.childFile('pubspec.yaml').writeAsStringSync('''
name: puro
version: 2.0.0
''');
          bundleDir.childFile('pubspec.lock').writeAsStringSync('''
packages:
  puro:
    version: "2.0.0"
    source: hosted
''');

          final scope = createTestScope(
            fileSystem: fs,
            executablePathOverride: exePath,
            isForkOverride: true,
          );

          final puroVersion = await PuroVersion.of(scope);

          expect(puroVersion.type, equals(PuroInstallationType.appBundle));
          expect(puroVersion.semver.toString(), equals('2.0.0-fork'));
        },
      );

      test('Scenario d: Non-fork resolution -> resolves 2.0.0+315c01e', () async {
        final fs = MemoryFileSystem();
        const exePath =
            '/Dart/install/app-bundles/puro/git/315c01edeba18abb0e7a766d5bf0f352f6d543b5/bundle/bin/puro';
        fs.file(exePath).createSync(recursive: true);

        final bundleDir = fs.file(exePath).parent.parent.parent;
        bundleDir.childFile('pubspec.yaml').writeAsStringSync('''
name: puro
version: 2.0.0
''');
        bundleDir.childFile('pubspec.lock').writeAsStringSync('''
packages:
  puro:
    version: "2.0.0"
    source: git
    description:
      resolved-ref: 315c01edeba18abb0e7a766d5bf0f352f6d543b5
''');

        final scope = createTestScope(
          fileSystem: fs,
          executablePathOverride: exePath,
          isForkOverride: false,
        );

        final puroVersion = await PuroVersion.of(scope);

        expect(puroVersion.type, equals(PuroInstallationType.appBundle));
        expect(puroVersion.semver.toString(), equals('2.0.0+315c01e'));
      });

      test(
        'Scenario e: Upstream define precedence over app-bundle layout',
        () async {
          final fs = MemoryFileSystem();
          const exePath =
              '/Dart/install/app-bundles/puro/git/315c01edeba18abb0e7a766d5bf0f352f6d543b5/bundle/bin/puro';
          fs.file(exePath).createSync(recursive: true);

          final bundleDir = fs.file(exePath).parent.parent.parent;
          bundleDir.childFile('pubspec.yaml').writeAsStringSync('''
name: puro
version: 1.0.0
''');

          final scope = createTestScope(
            fileSystem: fs,
            executablePathOverride: exePath,
            isForkOverride: true,
            puroVersionDefineOverride: '2.0.0',
          );

          final puroVersion = await PuroVersion.of(scope);

          expect(puroVersion.semver.toString(), equals('2.0.0-fork'));
        },
      );

      test(
        'Scenario f: puro upgrade-puro aborts on appBundle fork installations instructing user to run dart install --force',
        () async {
          final fs = MemoryFileSystem();
          final puroVersion = PuroVersion(
            semver: Version.parse('2.0.0-fork'),
            type: PuroInstallationType.appBundle,
            target: PuroBuildTarget.linuxX64,
            packageRoot: fs.directory(
              '/Dart/install/app-bundles/puro/git/315c01edeba18abb0e7a766d5bf0f352f6d543b5',
            ),
            puroExecutable: fs.file(
              '/Dart/install/app-bundles/puro/git/315c01edeba18abb0e7a766d5bf0f352f6d543b5/bundle/bin/puro',
            ),
            isFork: true,
          );

          final scope = createTestScope(fileSystem: fs, version: puroVersion);
          final runner = TestPuroCommandRunner(scope)
            ..addCommand(PuroUpgradeCommand());

          final result = await runner.run(['upgrade-puro']);
          expect(result, isNotNull);
          expect(result!.toModel().success, isFalse);
          final output = result
              .toModel()
              .messages
              .map((m) => m.message)
              .join('\n');
          expect(output, contains('dart install --force'));
          expect(
            output,
            contains('https://github.com/RandalSchwartz/puro.git'),
          );
        },
      );

      test(
        'Scenario f (non-fork): puro upgrade-puro aborts on appBundle upstream installations instructing user to run dart install --force puro',
        () async {
          final fs = MemoryFileSystem();
          final puroVersion = PuroVersion(
            semver: Version.parse('2.0.0'),
            type: PuroInstallationType.appBundle,
            target: PuroBuildTarget.linuxX64,
            packageRoot: fs.directory(
              '/Dart/install/app-bundles/puro/hosted/2.0.0',
            ),
            puroExecutable: fs.file(
              '/Dart/install/app-bundles/puro/hosted/2.0.0/bundle/bin/puro',
            ),
            isFork: false,
          );

          final scope = createTestScope(fileSystem: fs, version: puroVersion);
          final runner = TestPuroCommandRunner(scope)
            ..addCommand(PuroUpgradeCommand());

          final result = await runner.run(['upgrade-puro']);
          expect(result, isNotNull);
          expect(result!.toModel().success, isFalse);
          final output = result
              .toModel()
              .messages
              .map((m) => m.message)
              .join('\n');
          expect(output, contains('dart install --force puro'));
        },
      );
    },
  );
}
