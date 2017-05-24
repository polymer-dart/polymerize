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
    await _generateCommand(command.command);
    return;
  } else if (command.command?.name == 'html') {
    await _generateHtmlCommand(command.command);
    return;
  } else if (command.command?.name == 'gen_and_build') {
    await _generateAndBuildCommand(command.command);
    return;
  }

  List<String> summariesPaths = command['summary'];
  String outputPath = command['output'];
  String inputUri = command['input'];
  String genPath = command['generate'];

  await _ddcBuild(inputUri, summariesPaths, outputPath, genPath);
}

class Buffer implements StreamConsumer<List<int>> {
  List<List<int>> _buffer = [];

  @override
  Future addStream(Stream<List<int>> stream) async {
    await for (List<int> x in stream) {
      _buffer.add(x);
    }
  }

  @override
  Future close() async {}

  IOSink createSink() => new IOSink(this);

  Stream<String> get stream => new Stream.fromIterable(_buffer).transform(UTF8.decoder);
}

Future _generateAndBuildCommand(ArgResults command) async {
  String inputUri = command['input'];
  String genPath = command['generate'];
  List<String> summariesPaths = command['summary'];
  String outputPath = command['output'];
  String htmlPath = command['html'];
  List<String> depsPaths = command['dep'] ?? <String>[];

  Buffer _buf = new Buffer();
  IOSink htmlTemp = _buf.createSink();
  await generateCode(inputUri, genPath, htmlTemp);
  await _ddcBuild(inputUri, summariesPaths, outputPath, genPath);
  await _generateHtml(inputUri, htmlPath, outputPath, _buf.stream, depsPaths);
}

Future _ddcBuild(String inputUri, List<String> summariesPaths, String outputPath, String genPath) async {
  String genUri = inputUri.replaceFirst(new RegExp(r".dart$"), "_g.dart");

  int exitCode = await ddcStandalone([]
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

// Future<int> ddc(List<String> args) async => (await driver.doWork(new WorkRequest()..arguments.addAll(args))).exitCode;

Future<int> ddcStandalone(List<String> args) async {
  ProcessResult res =  (await Process.run('${findDartSDKHome().path}/dartdevc', args));
  if (res.exitCode!=0) {
    throw "ERROR ${res.stderr}\nOUTPUT ${res.stdout}";
  }
  return res.exitCode;
}

BazelWorkerDriver _driver;

BazelWorkerDriver get driver {
  if (_driver == null) {
    _driver = new BazelWorkerDriver(() async {
      Process proc = await Process.start('${findDartSDKHome().path}/dartdevc', ['--persistent_worker']);
      stderr.addStream(proc.stderr); // Read stderr
      return proc;
    }, maxWorkers: 1);
  }
  return _driver;
}

/**
 * Will generate code to initialize the module
 */
Future _generateCommand(ArgResults command) async {
  String inputUri = command['input'];
  String genPath = command['generate'];
  String htmlTemp = command['temp'];
  IOSink _sink = new File(htmlTemp).openWrite();
  await generateCode(inputUri, genPath, _sink);
  await _sink.close();
}

/**
 * Will generate a stub HTML that :
 *  1. will load the JS
 *  2. will execute the `initModule` method on the generated package
 *
 */
Future _generateHtmlCommand(ArgResults command) async {
  String outputPath = command['output'];
  String htmlPath = command['html'];
  String inputUri = command['input'];
  String htmlTemp = command['temp'];
  List<String> depsPaths = command['dep'] ?? <String>[];

  File f = new File(htmlTemp);
  Stream<String> htmlTempLines = new Stream.fromIterable(await f.readAsLines());
  await _generateHtml(inputUri, htmlPath, outputPath, htmlTempLines, depsPaths);
  await f.delete();
}

Future _generateHtml(String inputUri, String htmlPath, String outputPath, Stream<String> htmlTemp, List<String> depsPaths) async {
  String genUri = inputUri.replaceFirst(new RegExp(r".dart$"), "_g.dart");

  // And generate an html too
  File html = new File(htmlPath);
  IOSink sink = html.openWrite();

  String htmlDir = path.dirname(htmlPath);
  String moduleName = path.withoutExtension(path.relative(outputPath, from: BAZEL_BASE_DIR));

  toModuleName(String uri) => Uri.parse(uri).pathSegments.sublist(1).map((x) => path.withoutExtension(x)).join("__");

  await sink.addStream(() async* {
    yield* htmlTemp;
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
