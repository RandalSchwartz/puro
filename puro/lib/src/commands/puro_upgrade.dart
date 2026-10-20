import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

import '../command.dart';
import '../command_result.dart';
import '../config.dart';
import '../http.dart';
import '../install/upgrade.dart';
import '../process.dart';
import '../terminal.dart';
import '../version.dart';

class PuroUpgradeCommand extends PuroCommand {
  PuroUpgradeCommand() {
    argParser.addFlag(
      'force',
      hide: true,
      help:
          'Installs a new puro executable even if it wont replace an existing one',
      negatable: false,
    );
    argParser.addFlag(
      'path',
      help: 'Whether or not to update the PATH automatically',
    );
  }

  @override
  final name = 'upgrade-puro';

  @override
  List<String> get aliases => ['update-puro'];

  @override
  String? get argumentUsage => '[version]';

  @override
  final description = 'Upgrades the puro tool to a new version';

  @override
  bool get allowUpdateCheck => false;

  @override
  Future<CommandResult> run() async {
    final force = argResults!['force'] as bool;
    final http = scope.read(clientProvider);
    final config = PuroConfig.of(scope);
    final puroVersion = await PuroVersion.of(scope);
    final currentVersion = puroVersion.semver;
    var targetVersionString = unwrapSingleOptionalArgument();

    if (puroVersion.type == PuroInstallationType.pub) {
      if (puroVersion.isFork) {
        return BasicMessageResult(
          'Automatic pub upgrade is disabled to protect fork installation.\n'
          'To update from the fork repository, run:\n'
          '  dart pub global activate --source git $forkRepository.git',
          success: false,
        );
      }
      final result = await runProcess(scope, Platform.resolvedExecutable, [
        'pub',
        'global',
        'activate',
        'puro',
      ]);
      if (result.exitCode == 0) {
        final stdout = result.stdout as String;
        if (stdout.contains('already activated at newest available version')) {
          return BasicMessageResult('Puro is up to date with $currentVersion');
        } else {
          return BasicMessageResult('Upgraded puro to latest pub version');
        }
      } else {
        return BasicMessageResult(
          '`dart pub global activate puro` failed with exit code ${result.exitCode}\n${result.stderr}'
              .trim(),
          success: false,
        );
      }
    } else if (puroVersion.type != PuroInstallationType.distribution &&
        !force) {
      return BasicMessageResult(
        "Can't upgrade: ${puroVersion.type.description}",
        success: false,
      );
    }

    if (puroVersion.isFork) {
      if (!force) {
        return BasicMessageResult(
          'Automatic binary upgrades are disabled to protect fork installation.\n'
          'To upgrade a fork installation, build from source or configure a custom builds URL.',
          success: false,
        );
      }
      if (config.isDefaultBuildsUrl) {
        return BasicMessageResult(
          'No custom builds URL configured for fork binary upgrade.\n'
          'Upgrading from puro.dev would overwrite this fork with upstream Puro.',
          success: false,
        );
      }
    }

    if (targetVersionString == 'master') {
      final exitCode = await upgradePuro(
        scope: scope,
        targetVersion: 'master',
        path: argResults!.wasParsed('path')
            ? argResults!['path'] as bool
            : null,
      );
      await runner.exitPuro(exitCode);
    }

    final Version targetVersion;
    if (targetVersionString == null) {
      final latestVersionResponse = await http.get(
        config.puroBuildsUrl.append(path: 'latest'),
      );
      HttpException.ensureSuccess(latestVersionResponse);
      targetVersionString = latestVersionResponse.body.trim();
      targetVersion = Version.parse(targetVersionString);
      if (currentVersion == targetVersion && !force) {
        return BasicMessageResult('Puro is up to date with $targetVersion');
      } else if (currentVersion > targetVersion && !force) {
        return BasicMessageResult(
          'Puro is a newer version $currentVersion than the available $targetVersion',
          type: CompletionType.indeterminate,
        );
      }
    } else {
      targetVersion = Version.parse(targetVersionString);
      if (currentVersion == targetVersion && !force) {
        return BasicMessageResult('Puro is the desired version $targetVersion');
      }
    }

    final exitCode = await upgradePuro(
      scope: scope,
      targetVersion: '$targetVersion',
      path: argResults!.wasParsed('path') ? argResults!['path'] as bool : null,
    );

    await runner.exitPuro(exitCode);
  }
}
