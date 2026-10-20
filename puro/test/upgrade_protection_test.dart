import 'dart:convert';
import 'dart:io';

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:http/http.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:puro/src/command.dart';
import 'package:puro/src/commands/puro_upgrade.dart';
import 'package:puro/src/commands/version.dart';
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
    return StreamedResponse(Stream.value(utf8.encode('1.5.0')), 200);
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
  if (version != null) {
    scope.add(PuroVersion.provider, Future.value(version));
  }
  return scope;
}

void main() {
  group('Version Command identifies fork build (Issue #1)', () {
    // Row 1: distribution | 1.5.0-fork | Puro 1.5.0-fork
    test('distribution 1.5.0-fork contains "Puro 1.5.0-fork"', () async {
      final fs = MemoryFileSystem();
      final puroVersion = PuroVersion(
        semver: Version.parse('1.5.0-fork'),
        type: PuroInstallationType.distribution,
        target: PuroBuildTarget.linuxX64,
        packageRoot: null,
        puroExecutable: fs.file('/usr/local/bin/puro'),
        isFork: true,
      );
      final scope = createTestScope(fileSystem: fs, version: puroVersion);
      final runner = TestPuroCommandRunner(scope)..addCommand(VersionCommand());

      final result = await runner.run(['version']);
      expect(result, isNotNull);
      final output = result!
          .toModel()
          .messages
          .map((m) => m.message)
          .join('\n');
      expect(output, contains('Puro 1.5.0-fork'));
      expect(result.toModel().success, isTrue);
    });

    // Row 2: distribution | 1.5.0-fork | fork: RandalSchwartz/puro
    test(
      'distribution 1.5.0-fork contains "fork: RandalSchwartz/puro"',
      () async {
        final fs = MemoryFileSystem();
        final puroVersion = PuroVersion(
          semver: Version.parse('1.5.0-fork'),
          type: PuroInstallationType.distribution,
          target: PuroBuildTarget.linuxX64,
          packageRoot: null,
          puroExecutable: fs.file('/usr/local/bin/puro'),
          isFork: true,
        );
        final scope = createTestScope(fileSystem: fs, version: puroVersion);
        final runner = TestPuroCommandRunner(scope)
          ..addCommand(VersionCommand());

        final result = await runner.run(['version']);
        expect(result, isNotNull);
        final output = result!
            .toModel()
            .messages
            .map((m) => m.message)
            .join('\n');
        expect(output, contains('fork: RandalSchwartz/puro'));
        expect(result.toModel().success, isTrue);
      },
    );

    // Row 3: development | 1.5.0-fork | Puro 1.5.0-fork
    test('development 1.5.0-fork contains "Puro 1.5.0-fork"', () async {
      final fs = MemoryFileSystem();
      final puroVersion = PuroVersion(
        semver: Version.parse('1.5.0-fork'),
        type: PuroInstallationType.development,
        target: PuroBuildTarget.linuxX64,
        packageRoot: fs.directory('/home/dev/puro'),
        puroExecutable: null,
        isFork: true,
      );
      final scope = createTestScope(fileSystem: fs, version: puroVersion);
      final runner = TestPuroCommandRunner(scope)..addCommand(VersionCommand());

      final result = await runner.run(['version']);
      expect(result, isNotNull);
      final output = result!
          .toModel()
          .messages
          .map((m) => m.message)
          .join('\n');
      expect(output, contains('Puro 1.5.0-fork'));
      expect(result.toModel().success, isTrue);
    });
  });

  group(
    'Background update check is suppressed for fork builds by default (Issue #1)',
    () {
      test(
        'no HTTP requests are sent to puro.dev and no update nag message is returned',
        () async {
          final fs = MemoryFileSystem();
          final mockClient = MockHttpClient();
          final puroVersion = PuroVersion(
            semver: Version.parse('1.5.0-fork'),
            type: PuroInstallationType.distribution,
            target: PuroBuildTarget.linuxX64,
            packageRoot: null,
            puroExecutable: fs.file('/usr/local/bin/puro'),
            isFork: true,
          );
          final scope = createTestScope(
            fileSystem: fs,
            version: puroVersion,
            httpClient: mockClient,
          );
          final runner = TestPuroCommandRunner(scope);

          final message = await checkIfUpdateAvailable(
            scope: scope,
            runner: runner,
            alwaysNotify: true,
          );

          expect(message, isNull);
          expect(
            mockClient.requestedUris
                .where((uri) => uri.host.contains('puro.dev'))
                .toList(),
            isEmpty,
          );
        },
      );
    },
  );

  group(
    'Puro upgrade-puro prevents upstream overwrite on pub install (Issue #1)',
    () {
      test(
        'pub install on fork rejects pub upgrade and prints git instructions',
        () async {
          final fs = MemoryFileSystem();
          final puroVersion = PuroVersion(
            semver: Version.parse('1.5.0-fork'),
            type: PuroInstallationType.pub,
            target: PuroBuildTarget.linuxX64,
            packageRoot: fs.directory('/home/.pub-cache/global_packages/puro'),
            puroExecutable: null,
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
          expect(
            output,
            contains(
              'dart pub global activate --source git https://github.com/RandalSchwartz/puro.git',
            ),
          );
        },
      );
    },
  );

  group('Puro upgrade-puro aborts binary download on distribution fork (Issue #1)', () {
    // Example 1: force_flag: false | download_action: not downloaded | expected_success: false |
    // expected_message: Automatic binary upgrades are disabled to protect fork installation
    test('distribution fork without force flag aborts binary upgrade', () async {
      final fs = MemoryFileSystem();
      final mockClient = MockHttpClient();
      final puroVersion = PuroVersion(
        semver: Version.parse('1.5.0-fork'),
        type: PuroInstallationType.distribution,
        target: PuroBuildTarget.linuxX64,
        packageRoot: null,
        puroExecutable: fs.file('/usr/local/bin/puro'),
        isFork: true,
      );
      final scope = createTestScope(
        fileSystem: fs,
        version: puroVersion,
        httpClient: mockClient,
      );
      final runner = TestPuroCommandRunner(scope)
        ..addCommand(PuroUpgradeCommand());

      final result = await runner.run(['upgrade-puro']);
      expect(result, isNotNull);
      expect(result!.toModel().success, isFalse);
      expect(mockClient.requestedUris, isEmpty);
      final output = result.toModel().messages.map((m) => m.message).join('\n');
      expect(
        output,
        contains(
          'Automatic binary upgrades are disabled to protect fork installation',
        ),
      );
    });

    // Example 2: force_flag: true | download_action: guarded | expected_success: false |
    // expected_message: No custom builds URL configured for fork binary upgrade
    test(
      'distribution fork with force flag and default builds URL aborts binary upgrade',
      () async {
        final fs = MemoryFileSystem();
        final mockClient = MockHttpClient();
        final puroVersion = PuroVersion(
          semver: Version.parse('1.5.0-fork'),
          type: PuroInstallationType.distribution,
          target: PuroBuildTarget.linuxX64,
          packageRoot: null,
          puroExecutable: fs.file('/usr/local/bin/puro'),
          isFork: true,
        );
        final scope = createTestScope(
          fileSystem: fs,
          version: puroVersion,
          httpClient: mockClient,
          puroBuildsUrl: Uri.parse('https://puro.dev/builds'),
        );
        final runner = TestPuroCommandRunner(scope)
          ..addCommand(PuroUpgradeCommand());

        final result = await runner.run(['upgrade-puro', '--force']);
        expect(result, isNotNull);
        expect(result!.toModel().success, isFalse);
        expect(mockClient.requestedUris, isEmpty);
        final output = result
            .toModel()
            .messages
            .map((m) => m.message)
            .join('\n');
        expect(
          output,
          contains('No custom builds URL configured for fork binary upgrade'),
        );
      },
    );
  });

  group('Non-fork backward compatibility (SCAR-PROC-47)', () {
    test('non-fork version output does not contain fork banner', () async {
      final fs = MemoryFileSystem();
      final puroVersion = PuroVersion(
        semver: Version.parse('1.5.0'),
        type: PuroInstallationType.distribution,
        target: PuroBuildTarget.linuxX64,
        packageRoot: null,
        puroExecutable: fs.file('/usr/local/bin/puro'),
        isFork: false,
      );
      final scope = createTestScope(fileSystem: fs, version: puroVersion);
      final runner = TestPuroCommandRunner(scope)..addCommand(VersionCommand());

      final result = await runner.run(['version']);
      expect(result, isNotNull);
      final output = result!
          .toModel()
          .messages
          .map((m) => m.message)
          .join('\n');
      expect(output, contains('Puro 1.5.0'));
      expect(output, isNot(contains('fork:')));
      expect(result.toModel().success, isTrue);
    });
  });
}
