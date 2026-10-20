import 'dart:io';

import '../config.dart';
import '../downloader.dart';
import '../extensions.dart';
import '../http.dart';
import '../logger.dart';
import '../process.dart';
import '../provider.dart';
import '../terminal.dart';
import '../version.dart';

Future<int> upgradePuro({
  required Scope scope,
  required String targetVersion,
  required bool? path,
}) async {
  final config = PuroConfig.of(scope);
  final terminal = Terminal.of(scope);
  final log = PuroLogger.of(scope);
  final puroVersion = await PuroVersion.of(scope);
  if (puroVersion.isFork && config.isDefaultBuildsUrl) {
    log.e('Cannot upgrade fork binary from upstream puro.dev');
    return 1;
  }
  final buildTarget = config.buildTarget;
  final tempFile = config.puroExecutableTempFile;

  tempFile.parent.createSync(recursive: true);
  await downloadFile(
    scope: scope,
    url: config.puroBuildsUrl.append(
      path:
          '$targetVersion/'
          '${buildTarget.name}/'
          '${buildTarget.executableName}',
    ),
    file: tempFile,
    description: 'Downloading puro $targetVersion',
  );
  if (!Platform.isWindows) {
    await runProcess(scope, 'chmod', ['+x', '--', tempFile.path]);
  }
  config.puroExecutableFile.deleteOrRenameSync();
  tempFile.renameSync(config.puroExecutableFile.path);

  terminal.flushStatus();
  final installProcess =
      await startProcess(scope, config.puroExecutableFile.path, [
        if (terminal.enableColor) '--color',
        if (terminal.enableStatus) '--progress',
        '--log-level=${log.level?.index ?? 0}',
        'install-puro',
        if (path != null)
          if (path) '--path' else '--no-path',
      ]);
  final stdoutFuture = installProcess.stdout
      .listen(stdout.add)
      .asFuture<void>();
  await installProcess.stderr.listen(stderr.add).asFuture<void>();
  await stdoutFuture;
  return installProcess.exitCode;
}
