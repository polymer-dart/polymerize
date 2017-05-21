import 'dart:async';

import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'package:polymerize/src/code_generator.dart';
import 'package:polymerize/src/utils.dart';
import 'package:path/path.dart' as path;

import 'package:bazel_worker/bazel_worker.dart';
import 'package:bazel_worker/driver.dart';

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

/**
 * Builds the library and the generated file in a single module or executes subcommands (html and generate)
 */
Future ddcBuild(ArgResults command) async {
  if (command.command?.name == 'generate') {
    await _generate(command.command);
    return;
  } else if (command.command?.name == 'html') {
    await _generateHtml(command.command);
    return;
  }

  List<String> summariesPaths = command['summary'];
  String outputPath = command['output'];
  String inputUri = command['input'];
  String genPath = command['generate'];

  String genUri = inputUri.replaceFirst(new RegExp(r".dart$"), "_g.dart");

  int exitCode = await ddc(
      []
        ..addAll(['--module-root=${BAZEL_BASE_DIR}'])
        ..addAll(summaryOpts(summariesPaths))
        ..addAll(['-o', outputPath])
        ..add('--url-mapping=${genUri},${genPath}')
        //..add('--inline-source-map')
        ..add(inputUri)
        ..add(genUri));

  if (exitCode != 0) {
    //logger.severe("Error during build :${res.stdout} ${res.stderr}");
    throw "ERROR COMPILING ${inputUri}";
  }



}

Future<int> ddc(List<String> args) async => (await driver.doWork(new WorkRequest()..arguments.addAll(args))).exitCode;

BazelWorkerDriver _driver = new BazelWorkerDriver(() =>Process.start('${findDartSDKHome().path}/dartdevc', ['--persistent_worker']),maxWorkers: 1);

BazelWorkerDriver get driver {
  if (_driver == null) {
    _driver =  new BazelWorkerDriver(() =>Process.start('${findDartSDKHome().path}/dartdevc', ['--persistent_worker']));
  }
  return _driver;
}


/**
 * Will generate code to initialize the module
 */
Future _generate(ArgResults command) async {
  String inputUri = command['input'];
  String genPath = command['generate'];
  String htmlTemp = command['temp'];

  await generateCode(inputUri, genPath,htmlTemp);
}

/**
 * Will generate a stub HTML that :
 *  1. will load the JS
 *  2. will execute the `initModule` method on the generated package
 *
 */
Future _generateHtml(ArgResults command) async {
  String outputPath = command['output'];
  String htmlPath = command['html'];
  String inputUri = command['input'];
  String htmlTemp = command['temp'];
  List<String> depsPaths = command['dep'] ?? <String>[];

  String genUri = inputUri.replaceFirst(new RegExp(r".dart$"), "_g.dart");

  // And generate an html too
  File html = new File(htmlPath);
  IOSink sink = html.openWrite();

  String htmlDir = path.dirname(htmlPath);
  String moduleName = path.withoutExtension(path.relative(outputPath, from: BAZEL_BASE_DIR));

  toModuleName(String uri) =>
    Uri.parse(uri).pathSegments.sublist(1).map((x)=>path.withoutExtension(x)).join("__");


  await sink.addStream(() async* {
    File f = new File(htmlTemp);
    yield await f.readAsString();
    await f.delete();
    for (String dep in depsPaths) {
      yield "<link rel='import' href='${path.relative(dep,from:htmlDir)}'>\n";
    }
    yield "<script "
        "src='${path.relative(outputPath,from:htmlDir)}' "
        "as='${moduleName}'></script>\n";
    yield "<script>require(['${moduleName}'],(module) =>  module.${toModuleName(genUri)}.initModule());</script>\n";
  }()
      .transform(UTF8.encoder));
  await sink.close();
}
