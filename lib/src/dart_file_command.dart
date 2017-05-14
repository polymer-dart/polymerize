import 'dart:async';

import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'package:polymerize/src/utils.dart';
import 'package:path/path.dart' as path;

Future ddcBuild(ArgResults command) async {
  List l;
  ProcessResult res = await Process.run(
      '${findDartSDKHome().path}/dartdevc',
      []
        ..addAll(['--module-root=bazel-out/local-fastbuild/bin'])
        ..addAll(command['summary'].isEmpty?[]:command['summary'].map((s) => ['-s', s]).reduce((a, b) => []..addAll(a)..addAll(b)))
        ..addAll(['-o', command['output']])
        ..add(command['input']));

  // And generate an html too
  File html = new File(command['html']);
  IOSink sink = html.openWrite();
  await sink.addStream(() async* {
    for(String dep in command['dep'] ?? <String>[]) {
      yield "<link rel='import' href='${path.relative(dep,from:path.dirname(command['html']))}'>\n";
    }
    yield "<script src='${path.relative(command['output'],from:path.dirname(command['html']))}'>\n";
  }().transform(UTF8.encoder));
  await sink.close();

  if (res.exitCode!=0) {
    //logger.severe("Error during build :${res.stdout} ${res.stderr}");
    throw "ERROR : ${res.stdout} - ${res.stderr}";
  }
}