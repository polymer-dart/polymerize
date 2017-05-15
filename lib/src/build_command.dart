import 'dart:async';
import 'dart:io';
import 'package:args/args.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:polymerize/src/dep_analyzer.dart';

Logger _logger = new Logger('polymerize');

Future build(ArgResults command) async {
  String bower_resolutions_path = command['bower-resolutions'];
  String dart_bin_path = command['dart-bin-path'];
  String rules_version = command['rules-version'];
  String develop_path = command['develop'];


  String root;
  if (command.rest.isEmpty) {
    root = path.current;
  } else {
    root = command.rest.single;
  }

  _logger.info("Updating build files ...");
  WorkspaceBuilder builder = await WorkspaceBuilder.create(root, root,
                                                           dart_bin_path: dart_bin_path,
                                                           rules_version: rules_version,
                                                           develop_path: develop_path,
                                                           bower_resolutions: bower_resolutions_path);

  await builder.generateBuildFiles();

  // Then run bazel

  _logger.info("Running bazel ...");
  Process bazel = await Process.start('bazel',['build',':all']);
  stdout.addStream(bazel.stdout);
  stderr.addStream(bazel.stderr);

  await bazel.exitCode;

}