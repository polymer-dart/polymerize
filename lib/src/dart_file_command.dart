import 'dart:async';

import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'package:polymerize/src/utils.dart';
import 'package:path/path.dart' as path;

const String BAZEL_BASE_DIR = 'bazel-out/local-fastbuild/bin';

Iterable<String> summaryOpts(List<String> summaries) sync* {
  if (summaries == null) {
    return;
  }

  for (String summary in summaries) {
    yield '-s';
    yield summary;
  }
}

Future ddcBuild(ArgResults command) async {
  List l;

  ProcessResult res = await Process.run(
      '${findDartSDKHome().path}/dartdevc',
      []
        ..addAll(['--module-root=${BAZEL_BASE_DIR}'])
        ..addAll(summaryOpts(command['summary']))
        ..addAll(['-o', command['output']])
        ..add(command['input']));

  // And generate an html too
  File html = new File(command['html']);
  IOSink sink = html.openWrite();

  String htmlDir = path.dirname(command['html']);

  await sink.addStream(() async* {
    yield "<link rel='import' href='${path.relative('${BAZEL_BASE_DIR}/dart_sdk.mod.html',from:htmlDir)}'>\n";
    for (String dep in command['dep'] ?? <String>[]) {
      yield "<link rel='import' href='${path.relative(dep,from:htmlDir)}'>\n";
    }
    yield "<script "
        "src='${path.relative(command['output'],from:htmlDir)}' "
        "as='${path.withoutExtension(path.relative(command['output'],from: BAZEL_BASE_DIR))}'>\n";
  }()
      .transform(UTF8.encoder));
  await sink.close();

  if (res.exitCode != 0) {
    //logger.severe("Error during build :${res.stdout} ${res.stderr}");
    throw "ERROR : ${res.stdout} - ${res.stderr}";
  }
}
