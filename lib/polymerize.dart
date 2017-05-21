import 'package:analyzer/src/generated/engine.dart';
import 'package:html/dom.dart' as dom;
import 'package:path/path.dart' as path;
import 'package:analyzer/src/generated/source.dart';
import 'dart:io';
import 'dart:async';
import 'package:polymerize/src/bower_library.dart';
import 'package:polymerize/src/dart_file_command.dart';
import 'package:polymerize/src/wrapper_generator.dart';
import 'package:stack_trace/stack_trace.dart';
import 'package:resource/resource.dart' as res;
import 'package:args/args.dart';
import 'package:homedir/homedir.dart' as user;
import 'package:logging/logging.dart' as log;
import 'package:logging_handlers/logging_handlers_shared.dart';

import 'package:polymerize/src/pub_command.dart';
import 'package:polymerize/src/build_command.dart' as build_cmd;
import 'package:args/src/arg_results.dart';
import 'package:polymerize/src/utils.dart';
import 'package:bazel_worker/bazel_worker.dart';

const String RULES_VERSION = 'v0.12.0';

Future _copyResource(String resx, String dest) async {
  res.Resource rsx = new res.Resource(resx);
  String content = await rsx.readAsString();
  return new File(dest).writeAsString(content);
}

/***
 * Analyze one HTML template
 */

class HtmlDocResume {
  Set<String> propertyPaths = new Set();
  Set<String> eventHandlers = new Set();
  Set<String> customElementsRefs = new Set();

  toString() => "props : ${propertyPaths} , events : ${eventHandlers}, ele : ${customElementsRefs}";
}

class Options {
  bool polymerize_imported = false;
  bool native_imported = false;
}

HtmlDocResume _analyzeHtmlTemplate(AnalysisContext context, String templatePath) {
  HtmlDocResume resume = new HtmlDocResume();
  Source source = context.sourceFactory.forUri(path.toUri(templatePath).toString());
  dom.Document doc = context.parseHtmlDocument(source);
  dom.Element domElement = doc.querySelector('dom-module');
  if (domElement == null) {
    return resume;
  }
  dom.Element templateElement = domElement.querySelector('template');
  if (templateElement == null) {
    return resume;
  }

  // Lookup all the refs
  _extractRefs(resume, templateElement);

  return resume;
}

_extractRefs(HtmlDocResume resume, dom.Element element) {
  if (element.localName.contains('-')) {
    resume.customElementsRefs.add(element.localName);
  }
  element.attributes.keys.forEach((k) {
    String val = element.attributes[k];
    if (k.startsWith('on-')) {
      resume.eventHandlers.add(val);
    } else {
      // Check for prop refs
      resume.propertyPaths.addAll(_extractRefsFromString(val));
    }
  });

  _extractRefsFromString(element.text);

  element.children.forEach((el) => _extractRefs(resume, el));
}

final RegExp _propRefRE = new RegExp(r"(\{\{|\[\[)!?([^}]+)(\}\}|\]\])");

final RegExp _funcCallRE = new RegExp(r'([^()]+)\(([^)]+)\)');

Iterable<String> _extractRefsFromString(String element) => _propRefRE.allMatches(element).map((x) => x.group(2));

String docResumeTemplate(HtmlDocResume resume) => resume == null
    ? "null"
    : """{
  props:[${resume.propertyPaths.map((x) => "'${x}'").join(',')}],
  events:[${resume.eventHandlers.map((x) => "'${x}'").join(',')}]
}""";

class BuildError {
  List messages;

  BuildError(this.messages);

  toString() => messages.join("\n");
}

log.Logger logger = new log.Logger("polymerize");

main(List<String> args) async {
  Chain.capture(() async {
    await _main(args);
  }, onError: (error, Chain chain) {
    if (error is BuildError) {
      logger.severe("BUILD ERROR : \n${error}", error);
    } else {
      logger.severe("ERROR: ${error}\n AT: ${chain.terse}", error);
    }
  });
}

_main(List<String> args) async {
  String homePath = user.homeDirPath;
  if (homePath == null) {
    homePath = "/tmp";
  }

  ArgParser parser = new ArgParser()
    ..addFlag('help', abbr: 'h', help: 'print usage')
    ..addFlag('persistent_worker', help: 'run as a bazel worker')
    ..addCommand(
        'generate-wrapper',
        new ArgParser()
          ..addSeparator("component wrapper generator")
          ..addOption('component-refs', help: 'Components references yaml')
          ..addOption('dest-path', help: 'Destination path')
          ..addOption('bower-needs-map', allowMultiple: true, help: 'bower needs')
          ..addOption('package-name', abbr: 'p', help: 'dest dart package name'))
    ..addCommand(
        'pub',
        new ArgParser()
          ..addSeparator("pub helper for bazel")
          ..addOption('package', abbr: 'p', help: 'package name')
          ..addOption('version', abbr: 'v', help: 'package version')
          ..addOption('dest', abbr: 'd', help: 'destination')
          ..addOption('pub-host', abbr: 'H', help: 'pub host url'))
    ..addCommand(
        "build",
        new ArgParser()
          ..addOption('bower-resolutions', defaultsTo: "bower_resolutions.yaml", abbr: 'B', help: '(Optional) Bower resolutions file')
          ..addOption('dart-bin-path', defaultsTo: findDartSDKHome().path, help: 'dart sdk path')
          ..addOption('rules-version', abbr: 'R', defaultsTo: RULES_VERSION, help: 'Bazel rules version')
          ..addOption('develop', help: "enable polymerize develop mode, with repo home at the given path"))
    ..addCommand('copy', new ArgParser()..addOption('list', abbr: 'l')..addOption('src', abbr: 's', allowMultiple: true)..addOption('dest', abbr: 'd', allowMultiple: true))
    ..addCommand('bower_library')
    ..addCommand(
        'dart_file',
        new ArgParser()
          ..addOption('generate', abbr: 'g')
          ..addOption('summary', abbr: 's', allowMultiple: true)
          ..addOption('input', abbr: 'i')
          ..addOption('output', abbr: 'o')
          ..addCommand('generate', new ArgParser()..addOption('temp', abbr: 't')..addOption('generate', abbr: 'g')..addOption('input', abbr: 'i'))
          ..addCommand(
              'html',
              new ArgParser()
                ..addOption('input', abbr: 'i')
                ..addOption('temp', abbr: 't')
                ..addOption('dep', abbr: 'd', allowMultiple: true)
                ..addOption('output', abbr: 'o')
                ..addOption('html', abbr: 'h')))
    ..addCommand('export_sdk', new ArgParser()..addOption('output', abbr: 'o')..addOption('html', abbr: 'h')..addOption('imd')..addOption('imd_html'));

  // Configure logger
  log.hierarchicalLoggingEnabled = true;
  log.Logger.root.onRecord.listen(new LogPrintHandler(printFunc: (x) => stderr.writeln(x)));
  log.Logger.root.level = log.Level.INFO;

  ArgResults results = parser.parse(args);
  bool workerMode = results['persistent_worker'];
  if (results.rest.isNotEmpty && results.rest.first.startsWith("@")) {
    String argFile = results.rest.first.substring(1);
    results = parser.parse(await new File(argFile).readAsLines());
  }

  if (workerMode) {
    //logger.severe("Starting worker");
    await runWorker(parser);
    //logger.info("Terminating worker");
    await driver?.terminateWorkers();
    //logger.info("Worker terminated");
    exit(0);
  } else {
    return processRequestArgs(parser, results);
  }
}

class AsyncPolymerizeWorker extends AsyncWorkerLoop {
  ArgParser parser;

  AsyncPolymerizeWorker(this.parser);

  /// Must return a [Future<WorkResponse>], since this is an
  /// [AsyncWorkerLoop].
  Future<WorkResponse> performRequest(WorkRequest request) async {
    try {
      await processRequest(parser, request.arguments);
      return new WorkResponse()..exitCode = EXIT_CODE_OK;
    } catch (error) {
      return new WorkResponse()..exitCode = EXIT_CODE_ERROR;
    }
  }
}

Future runWorker(ArgParser parser) => new AsyncPolymerizeWorker(parser).run();

Future processRequest(ArgParser parser, List<String> args) {
  ArgResults results = parser.parse(args);
  return processRequestArgs(parser, results);
}

Future processRequestArgs(ArgParser parser, ArgResults results) async {
  if (results['help']) {
    print("polymerize <CMD> <options>\n${parser.usage}\n");
    parser.commands.keys.forEach((cmd) {
      print("polymerize ${cmd}\n${parser.commands[cmd].usage}\n");
    });
    return;
  }

  if (results.command?.name == 'build') {
    await build_cmd.build(results.command);
    return;
  }

  if (results.command?.name == 'generate-wrapper') {
    await new Generator().runGenerateWrapper(results.command);
    return;
  }

  if (results.command?.name == 'bower_library') {
    await createBowerLibrary(results.command.rest.first);
    return;
  }

  if (results.command?.name == 'copy') {
    List<String> src = results.command['src'];
    List<String> dst = results.command['dest'];
    String listFile = results.command['list'];
    IOSink listSink;
    if (listFile != null) listSink = new File(listFile).openWrite();

    Iterator<String> dstI = dst.iterator;

    for (String s in src) {
      String d = (dstI..moveNext()).current;

      if (listSink != null) listSink.writeln("${s} -> ${d}");
      await new Directory(path.dirname(d)).create(recursive: true);
      await new File(s).copy(d);
    }

    if (listSink != null) await listSink.close();

    return;
  }

  if (results.command?.name == 'export_sdk') {
    await _exportSDK(results.command['output'], results.command['html']);
    await _exportRequireJs(results.command['imd'], results.command['imd_html']);
    return;
  }

  if (results.command?.name == 'dart_file') {
    await ddcBuild(results.command);
    return;
  }

  if (results.command?.name == 'pub') {
    await runPubMode(results.command);
    return;
  }
}

Future _exportSDK(String dest, String destHTML, [String format = "amd"]) async {
  String dir = path.join(findDartSDKHome().parent.path, 'lib', 'dev_compiler');
  if (format == "legacy") {
    //await _copyResource("package:dev_compiler/js/legacy/dart_sdk.js", dest);

    await new File(path.join(dir, 'legacy/dart_sdk.js')).copy(dest);
    //await _copyResource("package:dev_compiler/js/legacy/dart_library.js",
    //    path.join(dest.path, "dart_library.js"));
  } else if (format == "es6") {
    //await _copyResource("package:dev_compiler/js/es6/dart_sdk.js", dest);
    await new File(path.join(dir, 'es6/dart_sdk.js')).copy(dest);
  } else if (format == "amd") {
    await new File(path.join(dir, 'amd/dart_sdk.js')).copy(dest);
    //await _copyResource("package:dev_compiler/js/amd/dart_sdk.js", dest);
  }

  // export HTML
  await new File(destHTML).writeAsString("""<script src='${path.basename(dest)}' as='dart_sdk'></script>""");
}

Future _exportRequireJs(String dest, String dest_html) async {
  await _copyResource("package:polymerize/imd/imd.js", dest);
  await new File(dest_html).writeAsString("""<script src='${path.basename(dest)}'></script>
<script>
(function(scope){
  scope.define(['require'],function(require) {
    scope.require = function(ids, func) {
      return func.apply(null, ids.map(function(m) {
        return require(m);
      }));
    };
  });
})(this);
</script>
""");
  //return _copyResource("package:polymerize/imd/imd.html", dest_html);
}
