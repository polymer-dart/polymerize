import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:dev_compiler/src/analyzer/context.dart';
import 'package:dev_compiler/src/compiler/compiler.dart';
import 'package:analyzer/src/summary/package_bundle_reader.dart';
import 'package:dev_compiler/src/compiler/module_builder.dart';
import 'package:path/path.dart' as path;
import 'package:analyzer/src/generated/source.dart';
import 'package:polymerize/package_graph.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:stack_trace/stack_trace.dart';
import 'package:resource/resource.dart' as res;
import 'package:args/args.dart';
import 'package:homedir/homedir.dart' as user;
import 'package:logging/logging.dart' as log;
import 'package:archive/archive.dart';
import 'package:polymerize/wrapper_generator.dart';

const Map<ModuleFormat, String> _formatToString = const {
  ModuleFormat.amd: 'amd',
  ModuleFormat.es6: 'es6',
  ModuleFormat.common: 'common',
  ModuleFormat.legacy: 'legacy'
};

const Map<String, ModuleFormat> _stringToFormat = const {
  'amd': ModuleFormat.amd,
  'es6': ModuleFormat.es6,
  'common': ModuleFormat.common,
  'legacy': ModuleFormat.legacy
};

log.Logger logger = new log.Logger("polymerize");

Future _buildAll(String rootPath, Directory dest, ModuleFormat format,
    String repoPath) async {
  /*if (await dest.exists()) {
    await dest.delete(recursive:true);
  }*/

  if (dest != null && !await dest.exists()) await dest.create(recursive: true);

  repoPath = path.join(repoPath, _formatToString[format]);

  PackageGraph packageGraph = new PackageGraph.forPath(rootPath);

  // Build Packages in referse order

  Map summaries = {};
  await _buildPackage(
      rootPath, packageGraph.root, summaries, dest, repoPath, format);

  if (dest == null) {
    return;
  }

  // The order is irrelevant ---
  if (format == ModuleFormat.legacy) {
    await _copyResource("package:dev_compiler/js/legacy/dart_sdk.js",
        path.join(dest.path, "dart_sdk.js"));
    await _copyResource("package:dev_compiler/js/legacy/dart_library.js",
        path.join(dest.path, "dart_library.js"));
  } else if (format == ModuleFormat.es6) {
    await _copyResource("package:dev_compiler/js/es6/dart_sdk.js",
        path.join(dest.path, "dart_sdk.js"));
  } else if (format == ModuleFormat.amd) {
    await _copyResource("package:dev_compiler/js/amd/dart_sdk.js",
        path.join(dest.path, "dart_sdk.js"));

    await _copyResource(
        "package:polymerize/require.js", path.join(dest.path, "require.js"));
  }

  // If an index.html template exists use it

  // Copy everything
  Directory webDir = new Directory(path.join(rootPath, "web"));
  if (webDir.existsSync()) {
    _copyDir(webDir, dest);
  }
}

Future _copyResource(String resx, String dest) async {
  res.Resource rsx = new res.Resource(resx);
  String content = await rsx.readAsString();
  return new File(dest).writeAsString(content);
}

Future<List<String>> _buildPackage(
    String rootPath,
    PackageNode node,
    Map<PackageNode, List<String>> summaries,
    Directory dest,
    String summaryRepoPath,
    ModuleFormat format) async {
  List<String> result;

  result = summaries[node];
  if (result != null) {
    return result;
  }

  // Build this package

  Set deps = new Set();
  for (PackageNode dep in node.dependencies) {
    deps.addAll(await _buildPackage(
        rootPath, dep, summaries, dest, summaryRepoPath, format));
  }

  /*
  (await Future.wait(node.dependencies.map((PackageNode dep) => _buildPackage(
          rootPath, dep, summaries, dest, summaryRepoPath, format))))
      .forEach((List<String> sum) => deps.addAll(sum));
*/

  logger.fine("Building ${node.name}");

  result = new List.from(deps);
  result.add(await _buildOne(
      rootPath,
      node.name,
      new Directory.fromUri(node.location),
      dest,
      new Directory(path.joinAll([
        summaryRepoPath,
        node.name,
        node.version != null ? node.version : ""
      ])),
      result,
      node.dependencyType == PackageDependencyType.pub,
      format));

  summaries[node] = result;

  return result;
}

Future<String> _buildOne(
    String rootPath,
    String packageName,
    Directory location,
    Directory dest,
    Directory summaryDest,
    List<String> summaries,
    bool useRepo,
    ModuleFormat format,
    {ArgResults bazelModeArgs}) async {
  File repo_smap =
      new File(path.join(summaryDest.path, "${packageName}.js.map"));
  File sum = new File(path.join(summaryDest.path, "${packageName}.sum"));
  File repo_js = new File(path.join(summaryDest.path, "${packageName}.js"));

  if (!await dest.exists()) {
    await dest.create(recursive: true);
  }

  if (!await summaryDest.exists()) {
    await summaryDest.create(recursive: true);
  }
  String libPath = path.join(location.path, "lib");

  Map<String, String> mapping = new Map.fromIterable(
      bazelModeArgs['mapping'].map((x) => x.split('=')),
      key: (x) => x[0],
      value: (x) => x[1]);

  // If use repo (after collect and copy)
  // TODO : Spostare questa logica sotto
  // 1) buildare sempre dentro il repo
  // 2) a poi copiare sempre dal repo verso la dest
  Directory assetDir = new Directory(path.join(summaryDest.path, "assets"));

  Map<String, String> maps = null;
  if (!useRepo || !(repo_js.existsSync()) || !repo_smap.existsSync()) {
    // Collect sources from filesystem
    List<String> sources = [];
    if (!assetDir.existsSync()) {
      assetDir.createSync();
    }
    if (bazelModeArgs == null) {
      await _collectSourcesAndCopyResources(
          packageName, new Directory(libPath), sources, assetDir);
    } else {
      sources = bazelModeArgs['source'];
      summaries =
          bazelModeArgs['summary'].map((x) => path.absolute(x)).toList();
      if (!summaries.every((x) => new File(x).existsSync())) {
        throw "SOME SUMMARY DO NOT EXISTS!";
      }
      //print("IT's OKKKKKK!");

      // Build library map
      //print("LIUB: ${libPath}");
      maps = new Map.fromIterable(sources,
          key: (x) => "package:${packageName}/${path.relative(x,from:libPath)}",
          value: (x) => path.absolute(x));

      sources = maps.keys.toList();
      //print("URL MAP : ${maps}");
    }
    // print("  Collected : ${sources}");
    //print("  Summaries : ${summaries}");

    //SummaryDataStore summaryDataStore = new SummaryDataStore(summaries);
    //print("SUM 1 ");
    //summaryDataStore.bundles.forEach((b) => print(b.linkedLibraryUris));
    //print("SUM 2 ");
    AnalyzerOptions opts = new AnalyzerOptions(
        dartSdkPath: '/usr/lib/dart',
        customUrlMappings: maps,
        /*  packageRoot: path.join(rootPath, "packages"),*/
        summaryPaths: summaries);

    ModuleCompiler moduleCompiler = new ModuleCompiler(opts);
    CompilerOptions compilerOptions = new CompilerOptions();

    // print("MAPPING : ${mapping} - ${bazelModeArgs['base_path']}");
    //mapping[packageName] = path.relative(bazelModeArgs['output'],from:libPath);

    BuildUnit bu = new BuildUnit(packageName, path.absolute(location.path),
        sources, (source) => _moduleForLibrary(source, mapping: mapping));

    JSModuleFile res = moduleCompiler.compile(bu, compilerOptions);
    if (!res.isValid) {
      throw new BuildError(res.errors);
    }

    // Leggo il file delle regole per creare una mappa tra ingressi ed uscite
    List<String> lines =
        (await new File(bazelModeArgs['template_out']).readAsLines());
    Map<String, String> in_out_html = {};
    Map<String, String> html_templates = {};
    for (int i = 0; i < lines.length; i += 2) {
      in_out_html[lines[i]] = lines[i + 1];
      html_templates[path.relative(lines[i], from: libPath)] = lines[i];
    }

    // Copy files
    await Future.wait(in_out_html.keys
        .map((source) => new File(source).copy(in_out_html[source])));

    // Costruisco l'elenco dei file html
    //Map html_templates = new Map.fromIterable(bazelModeArgs['template'],
    //  key: (x) => path.relative(x,from:libPath),
    //  value : (x) => path.absolute(x));

    //  print("TEMPL : ${html_templates}");

    // Analizzo il modulo

    //if (bazelModeArgs==null)

    moduleCompiler.context.librarySources.forEach((Source src) {
      if (src.isInSystemLibrary) {
        return;
      }
      if (src.uri.scheme != 'package') {
        return;
      }
      if (src.uri.pathSegments.first != packageName) {
        return;
      }

      //print("OUT: ${bazelModeArgs['template_out']}");

      LibraryElement le = moduleCompiler.context.getLibraryElement(src);

      le?.units?.forEach((CompilationUnitElement e) async {
        //print("Unit : ${e.name}");
        e.types.forEach((ClassElement ce) {
          DartObject reg = getAnnotation(ce.metadata, isPolymerRegister);
          if (reg != null) {
            Map config = collectConfig(moduleCompiler.context, ce);

            String name = path.basenameWithoutExtension(e.name);

            bool native = reg.getField('native').toBoolValue();

            String tag = reg.getField('tagName').toStringValue();
            String template = reg.getField('template').toStringValue();
            //print("${ce.name} -> Found Tag  : ${tag} [${template}]");

            List<DartObject> uses = reg.getField('uses').toListValue();
            String pathThis = path.join(
                _moduleForUri(ce.source.uri, mapping: mapping), template);
            pathThis = path.dirname(pathThis);

            String reversePath = path.relative(
                _moduleForUri(ce.source.uri, mapping: mapping),
                from: pathThis);

            List<String> toImport = [];

            if (uses != null) {
              // print("USES : ${uses}");
              uses.forEach((DartObject obj) {
                DartType dartType = obj.toTypeValue();
                // print("TYPE : ${dartType.element}");
                ClassElement ce2 = dartType.element;
                // print("META : ${ce2.metadata}");
                if (ce2 != null) {
                  DartObject reg2 =
                      getAnnotation(ce2.metadata, isPolymerRegister);
                  if (reg2 != null) {
                    String template2 =
                        reg2.getField('template').toStringValue();
                    // print(
                    //    "Template : ${template2} , ${ce2.library.identifier} ,${ce2.source.uri}");
                    // Calc root path or this template

                    String path2 = path.joinAll([
                      _moduleForUri(ce2.source.uri, mapping: mapping),
                      template2
                    ]);

                    String relPath2 = path.relative(path2, from: pathThis);
                    // print("PATH ${path2} from ${pathThis}");
                    // print("Path relative : ${relPath2}");
                    toImport.add(relPath2);
                  }
                }
                // Lookup for an annotation
                //DartObject anno2 = getAnnotation(obj.toCl, matches)
              });
            }

            // Trovo il file relativo all'element
            String templatePath =
                path.join(path.dirname(e.source.fullName), template);

            String rel = path.relative(templatePath, from: libPath);

            String destTemplate = path.join(assetDir.path, rel);
            String renameTo =
                "${destTemplate.substring(0,destTemplate.length-5)}_orig.html";

            // adjust
            templatePath = html_templates[rel];
            String finalDest = in_out_html[html_templates[rel]];
            //print("ADJUSTED TEMPLATE : ${templatePath} -> ${finalDest}");

            if (new File(templatePath).existsSync()) {
              //print("found ${templatePath} -> ${destTemplate}");

              Directory tempDest = new Directory(path.dirname(renameTo));
              if (!tempDest.existsSync()) {
                tempDest.createSync(recursive: true);
              }

              new File(templatePath).copySync(renameTo);
              String htmlTemplate = htmlImportTemplate(
                  template: template,
                  packageName: packageName,
                  name: name,
                  className: ce.name,
                  tagName: tag,
                  config: config,
                  native: native,
                  mapping: mapping);
              List<String> _tmp = new File(finalDest).readAsLinesSync();

              List _jsImports = [
                "<link rel='import' href='${path.normalize(path.join(reversePath,relativePolymerElementPath(packageName,mapping)))}/polymerize.html'>",
                "<link rel='import' href='${path.normalize(path.join(reversePath,packageName))}.mod.html'>"
              ];

              if (native) {
                _jsImports.add(
                    "<link rel='import' href='${path.normalize(path.join(reversePath,relativePolymerElementPath(packageName,mapping)))}/native_import.html'>");
              }

              _tmp = toImport
                  .map((x) => "<link rel='import' href='${x}'>")
                  .toList()..addAll(_jsImports)..addAll(_tmp);

              new File(finalDest).writeAsStringSync(
                _tmp.join("\n") + htmlTemplate, /*mode: FileMode.APPEND*/
              );
              new File(destTemplate).writeAsStringSync(htmlTemplate);
            }
          } else if ((reg = getAnnotation(ce.metadata, isDefine)) != null) {
            String tag = reg.getField('tagName').toStringValue();
            String htmlFile = reg.getField('htmlFile').toStringValue();

            String name = path.basenameWithoutExtension(e.name);

            String templatePath =
                path.join(path.dirname(e.source.fullName), htmlFile);

            String rel = path.relative(templatePath, from: libPath);

            String destTemplate = path.join(assetDir.path, rel);
            new File(destTemplate).writeAsStringSync(webComponentTemplate(
                packageName: packageName,
                name: name,
                className: ce.name,
                tagName: tag));
          }
        });
      });
    });

    //print("${_moduleForPackage(packageName,mapping:mapping)} DEPS: ${dependencies}");

    // Write outputs
    JSModuleCode code = res.getCode(format, false, "${packageName}.js", "");
    await repo_js.writeAsString(code.code);

    // Write source map
    await repo_smap.writeAsString(JSON.encode(code.sourceMap));

    // Write summary

    //File sum = new File(path.join(summaryDest.path, "${packageName}.sum"));
    await sum.writeAsBytes(res.summaryBytes);

    logger.fine(" - ${sum.path}");
  } else {
    // print("CACHED :  ${sum.path}");
  }

  if (dest != null) {
    File smap;
    File js;

    if (bazelModeArgs == null) {
      js = new File(path.join(dest.path, packageName, "${packageName}.js"));
      smap =
          new File(path.join(dest.path, packageName, "${packageName}.js.map"));
    } else {
      js = new File(bazelModeArgs['output']);
      await sum.copy(bazelModeArgs['output_summary']);
      //print("BZLBUILD Out       :${bazelModeArgs['output']}");
      //print("BZLBUILD Sum. Out  :${bazelModeArgs['output_summary']}");

      // WRITE HTML STUB
      var html = new File(bazelModeArgs['output_html']);
      // TODO : Aggiungere un import per ogni dipendenza - aggiungere l'import
      // per ogni template

      //print("MAPPIUNG : ${mapping}");
      await html.writeAsString("""
<link rel='import' href='${path.relative("dart_sdk.html",from:path.dirname(mapping[packageName]))}'>
${importDeps(mapping,packageName)}
<script src='${path.basename(js.path)}' as='${mapping[packageName]}'></script>
""");
    }

    await new Directory(path.join(dest.path, packageName)).create();

    // Copy From Build Repo
    await repo_js.copy(js.path);
    if (smap != null) await repo_smap.copy(smap.path);
    await _copyDir(assetDir, new Directory(path.join(dest.path, packageName)));
  }
  return sum.path;
}

String importDeps(Map<String, String> mapping, String packageName) => mapping
    .keys
    .where((k) => k != packageName)
    .map((k) =>
        "<link rel='import' href='${relativeModulePath(k,from:packageName,mapping:mapping)}.mod.html'>")
    .join('\n');

String relativeModulePath(String module,
        {String from, Map<String, String> mapping}) =>
    path.relative(mapping[module], from: path.dirname(mapping[from]));

Map collectConfig(AnalysisContext context, ClassElement ce) {
  List<String> observers = [];
  Map<String, Map> properties = {};

  ce.methods.forEach((MethodElement me) {
    DartObject obs = getAnnotation(me.metadata, isObserve);
    if (obs == null) {
      return;
    }

    String params = obs.getField('observed').toStringValue();

    observers.add("${me.name}(${params})");
  });

  ce.fields.forEach((FieldElement fe) {
    DartObject not = getAnnotation(fe.metadata, isNotify);
    properties[fe.name] = {'notify': not != null};
  });

  return {'observers': observers, 'properties': properties};
}

final Uri POLYMER_REGISTER_URI =
    Uri.parse('package:polymer_element/polymer_element.dart');

bool isPolymerRegister(DartObject o) =>
    (o.type.element.librarySource.uri == POLYMER_REGISTER_URI) &&
    (o.type.name == 'PolymerRegister');

bool isDefine(DartObject o) =>
    (o.type.element.librarySource.uri == POLYMER_REGISTER_URI) &&
    (o.type.name == 'Define');

bool isObserve(DartObject o) =>
    (o.type.element.librarySource.uri == POLYMER_REGISTER_URI) &&
    (o.type.name == 'Observe');

bool isNotify(DartObject o) =>
    (o.type.element.librarySource.uri == POLYMER_REGISTER_URI) &&
    (o.type.name == 'Notify');

DartObject getAnnotation(
        Iterable<ElementAnnotation> metadata, //
        bool matches(DartObject)) =>
    metadata
        .map((ElementAnnotation an) => an.computeConstantValue())
        .firstWhere(matches, orElse: () => null);

String webComponentTemplate(
        {String template,
        String packageName,
        String name,
        String className,
        String tagName}) =>
    """
<script>
  define(['${packageName}/${packageName}','polymer_element/polymerize'],function(pkg,polymerize) {
  polymerize.define('${tagName}',pkg.${name}.${className});
});
</script>
""";

String polymerElementPath(Map<String, String> mapping) =>
    _moduleForPackage('polymer_element', mapping: mapping);

String relativePolymerElementPath(String from, Map<String, String> mapping) =>
    path.dirname(
        relativeModulePath('polymer_element', from: from, mapping: mapping));

String htmlImportTemplate(
        {String template,
        String packageName,
        String name,
        String className,
        String tagName,
        Map config,
        bool native,
        Map<String, String> mapping}) =>
    """
${native?nativePreloadScript(tagName,['PolymerElements',className],polymerElementPath(mapping)):""}
<script>
  define('${tagName}',['${_moduleForPackage(packageName,mapping:mapping)}/${packageName}','${polymerElementPath(mapping)}/polymerize'],function(pkg,polymerize) {
  polymerize.register(pkg.${name}.${className},'${tagName}',${configTemplate(config)},${native});
});
</script>
""";

String nativePreloadScript(
        String tagName, List<String> classPath, String polymerElementPath) =>
    """
<script>
 define('${tagName}-native-import',['${polymerElementPath}/native_import'],function(util) {
   util.importNative('${tagName}',${classPath.map((s) => '\'${s}\'').join(',')});
 });
</script>
""";

String configTemplate(Map config) => (config == null || config.isEmpty)
    ? "null"
    : """
  {
    observers:[${config['observers'].map((x) => '"${x}"').join(',')}],
    properties: {
      ${configPropsTemplate(config['properties'])}
    }
  }""";

String configPropsTemplate(Map properties) => properties.keys
    .map((String propName) =>
        "${propName} : { notify: ${properties[propName]['notify']}}")
    .join(',\n      ');

DartType metadataType(ElementAnnotation meta) {
  if (meta is ConstructorElement) {
    return (meta as ConstructorElement).returnType;
  }
  return null;
}

class BuildError {
  List messages;

  BuildError(this.messages);

  toString() => messages.join("\n");
}

Future _collectSourcesAndCopyResources(String packageName, Directory dir,
    List<String> sources, Directory dest) async {
  if (!await dir.exists()) {
    return [];
  }
  //dest = new Directory(path.join(dest.path, packageName));
  await for (FileSystemEntity e in dir.list(recursive: true)) {
    String rel = path.relative(e.path, from: dir.path);

    if (e is File) {
      if (path.extension(e.path) == '.dart' &&
          !path.basename(e.path).startsWith('.')) {
        sources.add("package:${packageName}/${rel}");
      } else {
        String destPath = path.join(dest.path, rel);
        Directory p = new Directory(path.dirname(destPath));
        if (!await p.exists()) {
          await p.create(recursive: true);
        }
        e.copy(destPath);
      }
    }
  }
}

Future _copyDir(Directory srcDir, Directory dest) async {
  await for (FileSystemEntity e in srcDir.list(recursive: true)) {
    String rel = path.relative(e.path, from: srcDir.path);

    if (e is File) {
      String destPath = path.join(dest.path, rel);
      Directory p = new Directory(path.dirname(destPath));
      if (!await p.exists()) {
        await p.create(recursive: true);
      }
      e.copy(destPath);
    }
  }
}

String _moduleForLibrary(Source source, {Map<String, String> mapping}) {
  //print("MODULE FOR ${source}");
  if (source is InSummarySource) {
    //print ("SOURCES : ${source.summaryPath} , ${source.fullName} , ${moduleRoot}");

    RegExp re = new RegExp(r"^package:([^/]+).*$");
    Match m = re.matchAsPrefix(source.fullName);
    if (m == null) {
      throw "Source should be in package format :${source.fullName}";
    }

    return "${_moduleForPackage(m.group(1), mapping: mapping)}/${m.group(1)}";
  }

  throw 'Imported file "${source.uri}" was not found as a summary or source '
      'file. Please pass in either the summary or the source file '
      'for this import.';
}

String _moduleForPackage(String package, {Map<String, String> mapping}) {
  //print("MODULE FOR ${source}");
  //if (package == 'polymer_element') {
  //  return "external/polymer_element";
  //}

  String res = mapping[package];
  if (res != null) {
    return path.dirname(res);
  }

  return "${package}";
}

String _moduleForUri(Uri uri, {Map<String, String> mapping}) {
  RegExp re = new RegExp(r"^package:([^/]+).*$");
  Match m = re.matchAsPrefix(uri.toString());
  if (m == null) {
    throw "Source should be in package format :${uri}";
  }

  return _moduleForPackage(m.group(1), mapping: mapping);
}

main(List<String> args) {
  String homePath = user.homeDirPath;
  if (homePath == null) {
    homePath = "/tmp";
  }

  ArgParser parser = new ArgParser()
    ..addFlag('emit-output',
        abbr: 'e',
        negatable: true,
        defaultsTo: true,
        help: 'Should emit output')
    ..addOption('output',
        abbr: 'o', defaultsTo: 'out', help: 'output directory')
    ..addOption('repo',
        defaultsTo: path.join(homePath, '.polymerize'),
        help: 'Repository path (defaults to "\$HOME/.polymerize")')
    ..addOption('source',
        abbr: 's',
        defaultsTo: Directory.current.path,
        help: 'source package path')
    ..addOption('module-format',
        abbr: 'm',
        allowed:
            ModuleFormat.values.map((ModuleFormat x) => _formatToString[x]),
        defaultsTo: _formatToString[ModuleFormat.amd],
        help: 'module format')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'showHelp')
    ..addCommand(
        'bazel',
        new ArgParser()
          ..addOption('base_path', abbr: 'b', help: 'base package path')
          ..addOption('export-sdk', help: 'do export sdk')
          ..addOption('export-sdk-html', help: 'do export sdk HTML')
          ..addOption('export-requirejs', help: 'do export requirejs')
          ..addOption('export-require_html', help: 'do export requirehtml')
          ..addOption('source',
              abbr: 's', allowMultiple: true, help: 'dart source file')
          ..addOption('mapping',
              abbr: 'M', allowMultiple: true, help: 'external package mapping')
          ..addOption('template_out', abbr: 'T', help: 'html templates rule')
          ..addOption('summary',
              abbr: 'm', allowMultiple: true, help: 'dart summary file')
          ..addOption('output', abbr: 'o', help: 'output file')
          ..addOption('output_html', help: 'output html wrapper')
          ..addOption('output_summary', abbr: 'x', help: 'output summary file')
          ..addOption('package_name', abbr: 'p', help: 'the package name')
          ..addOption('package_version',
              abbr: 'v', help: 'the package version'))
    ..addCommand(
        'pub',
        new ArgParser()
          ..addOption('package', abbr: 'p', help: 'package name')
          ..addOption('version', abbr: 'v', help: 'package version')
          ..addOption('dest', abbr: 'd', help: 'destination')
          ..addOption('pub-host', abbr: 'H', help: 'pub host url'))
    ..addCommand(
        'generate-wrapper',
        new ArgParser()
          ..addOption('base-dir', abbr: 'b', help: 'base dir')
          ..addOption('file-path',
              allowMultiple: true, abbr: 'f', help: 'file path')
          ..addOption('package-name', abbr: 'p', help: 'dest packag')
          ..addOption('output-path',
              allowMultiple: true,
              abbr: 'F',
              help: 'corresponding generated wrappers')
          ..addFlag('help', help: 'help on generate'));

  // Configure logger
  log.Logger.root.onRecord.listen((log.LogRecord rec) {
    print("${rec.message}");
  });
  log.Logger.root.level = log.Level.INFO;

  ArgResults results = parser.parse(args);

  if (results['help']) {
    print(parser.usage);
    return;
  }

  String sourcePath = results['source'];

  String destPath = results['output'];

  if (false == results['emit-output']) {
    destPath = null;
  }

  String repoPath = results['repo'];

  ModuleFormat fmt = _stringToFormat[results['module-format']];

  if (results.command?.name == 'bazel') {
    runInBazelMode(sourcePath, destPath, repoPath, fmt, results.command);
    return;
  }

  if (results.command?.name == 'pub') {
    runPubMode(results.command);
    return;
  }

  if (results.command?.name == 'generate-wrapper') {
    if (results.command['help']) {
      print(
          "generate-wrapper usage :\n${parser.commands['generate-wrapper'].usage}");
      return;
    }
    new Generator().runGenerateWrapper(results.command);
    return;
  }

  Chain.capture(() {
    _buildAll(sourcePath, destPath == null ? null : new Directory(destPath),
        fmt, repoPath);
  }, onError: (error, Chain chain) {
    if (error is BuildError) {
      logger.severe("BUILD ERROR : \n${error}", error);
    } else {
      logger.severe("ERROR: ${error}\n AT: ${chain.terse}", error);
    }
  });
}

const Map _HEADERS = const {"Content-Type": "application/json"};

Future runPubMode(ArgResults params) async {
  // Ask pub to download
  var baseApiUrl = params['pub-host'] ?? "https://pub.dartlang.org/api";
  var url = "$baseApiUrl/packages/${params['package']}";
  HttpClient client = new HttpClient();
  HttpClientRequest req = await client.getUrl(Uri.parse(url));
  req.headers.contentType = new ContentType('application', 'json');
  HttpClientResponse response = await req.close();
  if (response.statusCode >= 300) {
    throw "error resp";
  }

  String body =
      await response.transform(UTF8.decoder).fold("", (a, b) => a + b);

  Map res = JSON.decode(body);

  Map ver =
      res['versions'].firstWhere((Map x) => x['version'] == params['version']);

  String archive_url = ver['archive_url'];

  // print("RES: ${archive_url}");

  req = await client.getUrl(Uri.parse(archive_url));
  response = await req.close();
  List<int> allBytes = [];
  await response.transform(GZIP.decoder).forEach((x) => allBytes.addAll(x));

  Archive a = new TarDecoder().decodeBytes(allBytes);

  a.files.forEach((f) {
    new File(path.join(params['dest'], f.name))
      ..createSync(recursive: true)
      ..writeAsBytesSync(f.content);
  });

  client.close();
}

Future runInBazelMode(String rootPath, String destPath, String summaryRepoPath,
    ModuleFormat fmt, ArgResults params) async {
  String packageName = params['package_name'];
  String packageVersion = params['package_version'];

  //print("BZLBUILD Sources   :${params['source']}");
  //print("BZLBUILD Summaries :${params['summary']}");

  String basePath = params['base_path'];
  //print("BASE PATH : ${basePath}");

  if (basePath == null) {
    basePath = path.absolute(".");
  } else {
    basePath = new Directory(basePath).parent.path;
  }

  await _buildOne(
      rootPath,
      packageName,
      new Directory(basePath),
      new Directory(destPath),
      new Directory(path.joinAll([
        summaryRepoPath,
        packageName,
        packageVersion != null ? packageVersion : ""
      ])),
      [],
      params['summary'],
      fmt,
      bazelModeArgs: params);

  if (params['export-sdk'] != null) {
    await _exportSDK(params['export-sdk'], params['export-sdk-html'], fmt);
  }

  if (params['export-requirejs'] != null) {
    await _exportRequireJs(
        params['export-requirejs'], params['export-require_html']);
  }
}

Future _exportSDK(String dest, String destHTML,
    [ModuleFormat format = ModuleFormat.amd]) async {
  if (format == ModuleFormat.legacy) {
    await _copyResource("package:dev_compiler/js/legacy/dart_sdk.js", dest);
    //await _copyResource("package:dev_compiler/js/legacy/dart_library.js",
    //    path.join(dest.path, "dart_library.js"));
  } else if (format == ModuleFormat.es6) {
    await _copyResource("package:dev_compiler/js/es6/dart_sdk.js", dest);
  } else if (format == ModuleFormat.amd) {
    await _copyResource("package:dev_compiler/js/amd/dart_sdk.js", dest);
  }

  // export HTML
  await new File(destHTML).writeAsString(
      """<script src='${path.basename(dest)}' as='dart_sdk'></script>""");
}

Future _exportRequireJs(String dest, String dest_html) async {
  await _copyResource("package:polymerize/imd/imd.js", dest);
  await new File(dest_html).writeAsString("""
<script src='${path.basename(dest)}'></script>
<script>
(function(scope){
  scope.define(['require'],function(require) {
    scope.require = function(ids, func) {
      func.apply(null, ids.map(function(m) {
        return require(m);
      }));
    };
  });
})(this);
</script>
""");
  //return _copyResource("package:polymerize/imd/imd.html", dest_html);
}
