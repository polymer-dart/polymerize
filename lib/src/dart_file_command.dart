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

String toLibraryName(String uri) {
  Uri u = Uri.parse(uri);
  return u.pathSegments.map((x) => x.replaceAll('.', "_")).join("_")+"_G";
}


Future ddcBuild(ArgResults command) async {
  List l;

  List<String> summariesPaths = command['summary'];
  String outputPath = command['output'];
  String htmlPath = command['html'];
  String inputUri = command['input'];
  String genPath = command['generate'];
  List<String> depsPaths = command['dep'] ?? <String>[];

  String genUri = inputUri.replaceFirst(new RegExp(r".dart$"), "_g.dart");

  // Per ora genera in modo molto semplice
  IOSink sinkDart = new File(genPath).openWrite();
  await sinkDart.addStream(() async* {
    yield "library ${toLibraryName(inputUri)};\n\n";
    yield "import '${inputUri}';\n";
    yield "\n";
    yield "initModule() {\n";
    // TODO : write register code for each polymer element
    yield "  // TODO: write code here\n";
    yield "}\n";
  }()
                           .transform(UTF8.encoder));
  sinkDart.close();


  ProcessResult res = await Process.run(
      '${findDartSDKHome().path}/dartdevc',
      []
        ..addAll(['--module-root=${BAZEL_BASE_DIR}'])
        ..addAll(summaryOpts(summariesPaths))
        ..addAll(['-o', outputPath])
        ..add('--url-mapping=${genUri},${genPath}')
        ..add(inputUri)..add(genUri));

  // And generate an html too
  File html = new File(htmlPath);
  IOSink sink = html.openWrite();

  String htmlDir = path.dirname(htmlPath);

  String moduleName = path.withoutExtension(path.relative(outputPath,from: BAZEL_BASE_DIR));

  await sink.addStream(() async* {
    yield "<link rel='import' href='${path.relative('${BAZEL_BASE_DIR}/dart_sdk.mod.html',from:htmlDir)}'>\n";
    for (String dep in depsPaths) {
      yield "<link rel='import' href='${path.relative(dep,from:htmlDir)}'>\n";
    }
    yield "<script "
        "src='${path.relative(outputPath,from:htmlDir)}' "
        "as='${moduleName}'></script>\n";
    yield "<script>\n";
    yield " require('${moduleName}',function(module) {\n";
    yield "   module.${path.withoutExtension(Uri.parse(genUri).pathSegments.last)}.initModule();\n";
    yield " });\n";
    yield "</script>\n";
  }()
      .transform(UTF8.encoder));
  await sink.close();

  if (res.exitCode != 0) {
    //logger.severe("Error during build :${res.stdout} ${res.stderr}");
    throw "ERROR : ${res.stdout} - ${res.stderr}";
  }
}
