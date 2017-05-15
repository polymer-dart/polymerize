import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:dev_compiler/src/analyzer/context.dart';
import 'package:dev_compiler/src/compiler/compiler.dart';
import 'package:dev_compiler/src/compiler/command.dart' show ddcArgParser;
import 'package:analyzer/src/summary/package_bundle_reader.dart';
import 'package:dev_compiler/src/compiler/module_builder.dart';
import 'package:html/dom.dart' as dom;
import 'package:package_resolver/package_resolver.dart';
import 'package:path/path.dart' as path;
import 'package:analyzer/src/generated/source.dart';
import 'package:polymerize/package_graph.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:polymerize/src/dart_file_command.dart';
import 'package:polymerize/src/dep_analyzer.dart';
import 'package:stack_trace/stack_trace.dart';
import 'package:resource/resource.dart' as res;
import 'package:args/args.dart';
import 'package:homedir/homedir.dart' as user;
import 'package:logging/logging.dart' as log;
import 'package:logging_handlers/logging_handlers_shared.dart';

import 'package:polymerize/src/wrapper_generator.dart';
import 'package:polymerize/src/bower_command.dart';
import 'package:polymerize/src/init_command.dart';
import 'package:polymerize/src/pub_command.dart';
import 'package:polymerize/src/build_command.dart' as build_cmd;
import 'package:args/src/arg_results.dart';
import 'package:polymerize/src/utils.dart';

const Map<ModuleFormat, String> _formatToString = const {ModuleFormat.amd: 'amd', ModuleFormat.es6: 'es6', ModuleFormat.common: 'common', ModuleFormat.legacy: 'legacy'};

bool notNull(x) => x != null;

const Map<String, ModuleFormat> _stringToFormat = const {'amd': ModuleFormat.amd, 'es6': ModuleFormat.es6, 'common': ModuleFormat.common, 'legacy': ModuleFormat.legacy};

log.Logger logger = new log.Logger("polymerize");

Future _buildAll(String rootPath, Directory dest, ModuleFormat format, String repoPath) async {
  /*if (await dest.exists()) {
    await dest.delete(recursive:true);
  }*/

  if (dest != null && !await dest.exists()) await dest.create(recursive: true);

  repoPath = path.join(repoPath, _formatToString[format]);

  PackageGraph packageGraph = new PackageGraph.forPath(rootPath);

  // Build Packages in referse order

  Map<PackageNode, List<String>> summaries = <PackageNode, List<String>>{};
  await _buildPackage(rootPath, packageGraph.root, summaries, dest, repoPath, format);

  if (dest == null) {
    return;
  }

  // The order is irrelevant ---
  if (format == ModuleFormat.legacy) {
    await _copyResource("package:dev_compiler/js/legacy/dart_sdk.js", path.join(dest.path, "dart_sdk.js"));
    await _copyResource("package:dev_compiler/js/legacy/dart_library.js", path.join(dest.path, "dart_library.js"));
  } else if (format == ModuleFormat.es6) {
    await _copyResource("package:dev_compiler/js/es6/dart_sdk.js", path.join(dest.path, "dart_sdk.js"));
  } else if (format == ModuleFormat.amd) {
    await _copyResource("package:dev_compiler/js/amd/dart_sdk.js", path.join(dest.path, "dart_sdk.js"));

    await _copyResource("package:polymerize/require.js", path.join(dest.path, "require.js"));
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

Future<List<String>> _buildPackage(String rootPath, PackageNode node, Map<PackageNode, List<String>> summaries, Directory dest, String summaryRepoPath, ModuleFormat format) async {
  List<String> result;

  result = summaries[node];
  if (result != null) {
    return result;
  }

  // Build this package

  Set deps = new Set();
  for (PackageNode dep in node.dependencies) {
    deps.addAll(await _buildPackage(rootPath, dep, summaries, dest, summaryRepoPath, format));
  }

  /*
  (await Future.wait(node.dependencies.map((PackageNode dep) => _buildPackage(
          rootPath, dep, summaries, dest, summaryRepoPath, format))))
      .forEach((List<String> sum) => deps.addAll(sum));
*/

  logger.fine("Building ${node.name}");

  result = new List.from(deps);
  result.add(await _buildOne(rootPath, node.name, new Directory.fromUri(node.location), dest,
      new Directory(path.joinAll([summaryRepoPath, node.name, node.version != null ? node.version : ""])), result, node.dependencyType == PackageDependencyType.pub, format));

  summaries[node] = result;

  return result;
}

Future<String> _buildOne(String rootPath, String packageName, Directory location, Directory dest, Directory summaryDest, List<String> summaries, bool useRepo, ModuleFormat format,
    {ArgResults bazelModeArgs}) async {
  File repo_smap = new File(path.join(summaryDest.path, "${packageName}.js.map"));
  File sum = new File(path.join(summaryDest.path, "${packageName}.sum"));
  File repo_js = new File(path.join(summaryDest.path, "${packageName}.js"));

  if (!await dest.exists()) {
    await dest.create(recursive: true);
  }

  if (!await summaryDest.exists()) {
    await summaryDest.create(recursive: true);
  }
  String libPath = path.join(location.path, "lib");

  Map<String, String> mapping = new Map.fromIterable(bazelModeArgs['mapping'].map((x) => x.split('=')), key: (x) => x[0], value: (x) => x[1]);

  // If use repo (after collect and copy)
  // TODO : Spostare questa logica sotto
  // 1) buildare sempre dentro il repo
  // 2) a poi copiare sempre dal repo verso la dest
  Directory assetDir = new Directory(path.join(summaryDest.path, "assets"));

  List<BowerImport> bower_imports = <BowerImport>[];
  List<String> pre_dart = <String>[];
  List<String> post_dart = <String>[];
  Options options = new Options();

  Map<String, String> maps = null;
  if (!useRepo || !(repo_js.existsSync()) || !repo_smap.existsSync()) {
    // Collect sources from filesystem
    List<String> sources = [];
    if (!assetDir.existsSync()) {
      assetDir.createSync();
    }
    if (bazelModeArgs == null) {
      await _collectSourcesAndCopyResources(packageName, new Directory(libPath), sources, assetDir);
    } else {
      sources = bazelModeArgs['source'];
      summaries = bazelModeArgs['summary'].map((x) => path.absolute(x)).toList();
      if (!summaries.every((x) => new File(x).existsSync())) {
        throw "SOME SUMMARY DO NOT EXISTS!";
      }
      //print("IT's OKKKKKK!");

      // Build library map
      //print("LIUB: ${libPath}");
      maps = new Map.fromIterable(sources, key: (x) => "package:${packageName}/${path.relative(x,from:libPath)}", value: (x) => path.absolute(x));

      sources = maps.keys.toList();
      //print("URL MAP : ${maps}");
    }

    // print("  Collected : ${sources}");
    //print("  Summaries : ${summaries}");

    //SummaryDataStore summaryDataStore = new SummaryDataStore(summaries);
    //print("SUM 1 ");
    //summaryDataStore.bundles.forEach((b) => print(b.linkedLibraryUris));
    //print("SUM 2 ");
    AnalyzerOptions opts = new AnalyzerOptions.fromArguments(
        newArgResults(
            ddcArgParser(),
            {'D': [], 'dart-sdk': findDartSDKHome().parent.path, 'url-mapping': maps.keys.map((k) => "${k},${maps[k]}")},
            /*name*/ null,
            /*command*/ null,
            /*rest*/ null,
            /*arguments*/ null),
        summaryPaths: summaries);

    ModuleCompiler moduleCompiler = new ModuleCompiler(opts);
    CompilerOptions compilerOptions = new CompilerOptions();

    // print("MAPPING : ${mapping} - ${bazelModeArgs['base_path']}");
    //mapping[packageName] = path.relative(bazelModeArgs['output'],from:libPath);

    BuildUnit bu = new BuildUnit(packageName, path.absolute(location.path), sources, (source) => _moduleForLibrary(source, mapping: mapping));

    JSModuleFile res = moduleCompiler.compile(bu, compilerOptions);
    if (!res.isValid) {
      throw new BuildError(res.errors);
    }

    // Leggo il file delle regole per creare una mappa tra ingressi ed uscite
    List<String> lines = (await new File(bazelModeArgs['template_out']).readAsLines());
    Map<String, String> in_out_html = {};
    Map<String, String> html_templates = {};
    for (int i = 0; i < lines.length; i += 2) {
      in_out_html[lines[i]] = lines[i + 1];
      html_templates[path.relative(lines[i], from: libPath)] = lines[i];
    }

    // Copy files
    await Future.wait(in_out_html.keys.map((source) => new File(source).copy(in_out_html[source])));

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

      DartObject libJsAnno = getAnnotation(le.metadata, isJS);
      String jsNamespace = libJsAnno?.getField('name')?.toStringValue();

      le?.units?.forEach((CompilationUnitElement e) async {
        //print("Unit : ${e.name}");
        e.types.forEach((ClassElement ce) {
          Iterable<BowerImport> localImports = bowerImportsFor(ce);
          bower_imports.addAll(localImports);

          DartObject classJsAnno = getAnnotation(ce.metadata, isJS);
          String jsClass = classJsAnno?.getField('name')?.toStringValue();

          //print("SUPER : ${ce.supertype.element.name} ${ce.supertype.element}");
          jsClass ??= getAnnotation(ce.supertype.element.metadata, isJS)?.getField('name')?.toStringValue();

          DartObject reg = getAnnotation(ce.metadata, isPolymerRegister);
          if (reg != null) {
            _generateElementStub(
                pre_dart: pre_dart,
                post_dart: post_dart,
                options: options,
                jsNamespace: jsNamespace,
                jsClass: jsClass,
                ce: ce,
                e: e,
                moduleCompiler: moduleCompiler,
                reg: reg,
                mapping: mapping,
                libPath: libPath,
                html_templates: html_templates,
                in_out_html: in_out_html,
                packageName: packageName,
                bazelModeArgs: bazelModeArgs);
          } else {
            // If there isn't a `PolymerRegister` means we're defining a Dart Behavior
            reg = getAnnotation(ce.metadata, isPolymerBehavior);
            if (reg != null) {
              _generateBehaviorStub(
                  pre_dart: pre_dart,
                  post_dart: post_dart,
                  options: options,
                  jsNamespace: jsNamespace,
                  jsClass: jsClass,
                  ce: ce,
                  e: e,
                  moduleCompiler: moduleCompiler,
                  reg: reg,
                  mapping: mapping,
                  libPath: libPath,
                  html_templates: html_templates,
                  in_out_html: in_out_html,
                  packageName: packageName,
                  bazelModeArgs: bazelModeArgs);
            }
          }
        });
      });
    });

    //print("${_moduleForPackage(packageName,mapping:mapping)} DEPS: ${dependencies}");

    // Write outputs
    JSModuleCode code = res.getCode(
        format, path.toUri(path.join(dest.path, packageName, "${packageName}.js")).toString(), path.toUri(path.join(dest.path, packageName, "${packageName}.js.map")).toString());
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

    js = new File(bazelModeArgs['output']);
    await sum.copy(bazelModeArgs['output_summary']);
    //print("BZLBUILD Out       :${bazelModeArgs['output']}");
    //print("BZLBUILD Sum. Out  :${bazelModeArgs['output_summary']}");

    // WRITE HTML STUB
    var html = new File(bazelModeArgs['output_html']);
    // TODO : Aggiungere un import per ogni dipendenza - aggiungere l'import
    // per ogni template

    if (bazelModeArgs['bower-needs'] != null) {
      await new File(bazelModeArgs['bower-needs']).writeAsString(bower_imports.map((b) => '"${b.name}":"${b.ref}"').join("\n"));
    }

    //print("MAPPIUNG : ${mapping}");
    await html.writeAsString("""
<link rel='import' href='${path.relative("dart_sdk.html",from:path.dirname(mapping[packageName]))}'>
${importBowers(bower_imports,from:path.dirname(mapping[packageName]))}
${importDeps(mapping,packageName)}
${pre_dart.join("\n")}
<!-- Module Dart -->
<script src='${path.basename(js.path)}' as='${_fixModuleName(mapping[packageName])}'></script>
<!-- components reg -->
${post_dart.join("\n")}
""");

    await new Directory(path.join(dest.path, packageName)).create();

    // Copy From Build Repo
    await repo_js.copy(js.path);
    if (smap != null) await repo_smap.copy(smap.path);
    await _copyDir(assetDir, new Directory(path.join(dest.path, packageName)));
  }
  return sum.path;
}

String _fixModuleName(String modName) => modName.startsWith('external/') ? modName.substring(9) : modName;

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

void _generateBehaviorStub(
    {List<String> pre_dart,
    List<String> post_dart,
    ClassElement ce,
    ModuleCompiler moduleCompiler,
    DartObject reg,
    Map<String, String> mapping,
    String libPath,
    CompilationUnitElement e,
    Map<String, String> html_templates,
    Map<String, String> in_out_html,
    String packageName,
    String jsClass,
    String jsNamespace,
    ArgResults bazelModeArgs,
    Options options}) {
  Map config = collectConfig(moduleCompiler.context, ce);

  // Import utility module if needed
  if (!options.polymerize_imported) {
    //print('Packagename :${packageName} , mapping:${mapping}');
    post_dart.add("<link rel='import' href='${relativePolymerElementPath(packageName,mapping)}/polymerize.html'>");
    options.polymerize_imported = true;
  }

  String unitName = path.basenameWithoutExtension(e.name);
  String name = reg.getField('name').toStringValue();

  // Define behavior
  post_dart.add(defineBehaviorTemplate(behaviorName: name, config: config, packageName: packageName, mapping: mapping, name: unitName, className: ce.name));
}

void _generateElementStub(
    {List<String> pre_dart,
    List<String> post_dart,
    ClassElement ce,
    ModuleCompiler moduleCompiler,
    DartObject reg,
    Map<String, String> mapping,
    String libPath,
    CompilationUnitElement e,
    Map<String, String> html_templates,
    Map<String, String> in_out_html,
    String packageName,
    String jsClass,
    String jsNamespace,
    ArgResults bazelModeArgs,
    Options options}) {
  Map config = collectConfig(moduleCompiler.context, ce);

  String name = path.basenameWithoutExtension(e.name);

  bool native = reg.getField('native').toBoolValue();

  String tag = reg.getField('tagName').toStringValue();
  String template = reg.getField('template')?.toStringValue();
  //print("${ce.name} -> Found Tag  : ${tag} [${template}]");

  //List<DartObject> uses = reg.getField('uses')?.toListValue() ?? [];
  String pathThis = path.join(_moduleForUri(ce.source.uri, mapping: mapping), template ?? 'none.html');
  pathThis = path.dirname(pathThis);

  /*String reversePath = path.relative(
      _moduleForUri(ce.source.uri, mapping: mapping),
      from: pathThis);*/

  // Look for ReduxBehavior
  Map reduxInfo = ce.interfaces.map((intf) {
    ElementAnnotation anno = getElementAnnotation(intf.element.metadata, isStoreDef);
    if (anno == null) {
      return null;
    }

    //print("${anno.element.kind}");
    if (anno.element.kind == ElementKind.GETTER) {
      MethodElement m = anno.element;
      String mod = _moduleForUri(m.source.uri, mapping: mapping);
      List<String> p1 = path.split(m.source.uri.path).sublist(1);
      p1[p1.length - 1] = path.basenameWithoutExtension(p1.last);
      String p = p1.join('_');
      //print(
      //    "GETTER: ${m.name}, ${mod},${m.source.shortName}, path:${p}");
      return {'type': 'getter', 'name': m.name, 'source': p, 'module': mod};
    }
    DartObject reducer = anno.computeConstantValue().getField('reducer');
    new log.Logger('builder').finest("FOUND: ${reducer}");
    return reducer;
  }).firstWhere(notNull, orElse: () => {});

  // NOTE : toImport is deprecated and no more used

  // Trovo il file relativo all'element
  String templatePath;
  String finalDest = null;
  HtmlDocResume docResume;
  if (template != null) {
    templatePath = path.isAbsolute(template) ? path.join(libPath, template) : path.join(path.dirname(e.source.fullName), template);

    docResume = _analyzeHtmlTemplate(moduleCompiler.context, templatePath);

    String rel = path.relative(templatePath, from: libPath);

    //String destTemplate = path.join(assetDir.path, rel);

    // adjust
    templatePath = html_templates[rel];

    finalDest = in_out_html[html_templates[rel]];
  }

  //print("ADJUSTED TEMPLATE : ${templatePath} -> ${finalDest}");

  //if (templatePath!=null && new File(templatePath).existsSync()) {
  //print("found ${templatePath} -> ${destTemplate}");

  if (native) {
    if (!options.native_imported) {
      pre_dart.add("<link rel='import' href='${relativePolymerElementPath(packageName,mapping)}/native_import.html'>");
      options.native_imported = true;
    }
    pre_dart.add(nativePreloadScript(tag, jsNamespace.split('.')..add(jsClass), polymerElementPath(mapping)));
  } else if (!native && finalDest != null) {
    // TODO : embed template here ?
    pre_dart.add("<link rel='import' href='${path.normalize(path.relative(finalDest,from:path.dirname(bazelModeArgs['output_html'])))}'>");
  }

  if (!options.polymerize_imported) {
    post_dart.add("<link rel='import' href='${relativePolymerElementPath(packageName,mapping)}/polymerize.html'>");
    options.polymerize_imported = true;
  }
  post_dart.add(htmlImportTemplate(
      template: template,
      jsNamespace: jsNamespace,
      jsClassName: jsClass,
      packageName: packageName,
      name: name,
      className: ce.name,
      tagName: tag,
      config: config,
      resume: docResume,
      reduxInfo: reduxInfo,
      native: native,
      mapping: mapping));
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

importBowers(List<BowerImport> imports, {String from}) => imports.map((b) => "<link rel='import' href='${path.relative('bower_components',from:from)}/${b.import}'>").join("\n");

class BowerImport {
  String ref;
  String import;
  String name;
  BowerImport({this.ref, this.import, this.name});
}

Iterable<BowerImport> bowerImportsFor(ClassElement e) sync* {
  DartObject ref = getAnnotation(e.metadata, isBowerImport);
  if (ref != null) {
    yield new BowerImport(ref: ref.getField("ref").toStringValue(), import: ref.getField("import").toStringValue(), name: ref.getField("name").toStringValue());
  }
}

String importDeps(Map<String, String> mapping, String packageName) =>
    mapping.keys.where((k) => k != packageName).map((k) => "<link rel='import' href='${relativeModulePath(k,from:packageName,mapping:mapping)}.mod.html'>").join('\n');

String relativeModulePath(String module, {String from, Map<String, String> mapping}) => path.relative(mapping[module], from: path.dirname(mapping[from]));

Map collectConfig(AnalysisContext context, ClassElement ce) {
  List<String> observers = [];
  List<String> reduxActions = [];
  Map<String, Map> properties = {};

  ce.methods.forEach((MethodElement me) {
    DartObject obs = getAnnotation(me.metadata, isObserve);
    if (obs != null) {
      String params = obs.getField('observed').toStringValue();

      observers.add("${me.name}(${params})");
    }
    obs = getAnnotation(me.metadata, isReduxActionFactory);
    if (obs != null) {
      reduxActions.add(me.name);
    }
  });

  ce.fields.forEach((FieldElement fe) {
    DartObject not = getAnnotation(fe.metadata, isNotify);
    properties[fe.name] = {'notify': not != null};
    DartObject prop = getAnnotation(fe.metadata, isProperty);
    if (prop != null) {
      properties[fe.name]
        ..['notify'] = prop.getField('notify').toBoolValue()
        ..['statePath'] = prop.getField('statePath').toStringValue();
    }
  });

  String behaviorName(ClassElement intf, DartObject anno) {
    DartObject libAnno = getAnnotation(intf.library.metadata, isJS);
    String res = anno.getField('name').toStringValue();
    if (libAnno == null) {
      return res;
    } else {
      String pkg = libAnno.getField('name').toStringValue();
      return "${pkg}.${res}";
    }
  }

  Set<String> behaviors = new Set()
    ..addAll(ce.interfaces.map((InterfaceType intf) {
      DartObject anno = getAnnotation(intf.element.metadata, anyOf([isPolymerBehavior, isJS]));
      if (anno != null) {
        return behaviorName(intf.element, anno);
      } else {
        return null;
      }
    }).where(notNull));

  return {'observers': observers, 'properties': properties, 'reduxActions': reduxActions, 'behaviors': behaviors};
}

typedef bool matcher(DartObject x);

matcher anyOf(List<matcher> matches) => (DartObject o) => matches.any((m) => m(o));

String webComponentTemplate({String template, String packageName, String name, String className, String tagName}) => """<script>
  require(['${packageName}/${packageName}','polymer_element/polymerize'],function(pkg,polymerize) {
  polymerize.define('${tagName}',pkg.${name}.${className});
});
</script>""";

String polymerElementPath(Map<String, String> mapping) => _moduleForPackage('polymer_element', mapping: mapping);

String relativePolymerElementPath(String from, Map<String, String> mapping) => path.dirname(relativeModulePath('polymer_element', from: from, mapping: mapping));

String htmlImportTemplate(
        {String template,
        String packageName,
        String name,
        String className,
        String tagName,
        Map config,
        bool native,
        Map<String, String> mapping,
        HtmlDocResume resume,
        String jsNamespace,
        Map reduxInfo,
        String jsClassName}) =>
    """<script>
  require(['${_fixModuleName(path.normalize(_moduleForPackage(packageName,mapping:mapping)+'/'+packageName))}','${_fixModuleName(polymerElementPath(mapping))}/polymerize'],function(pkg,polymerize) {
  polymerize.register(pkg.${name}.${className},'${tagName}',${configTemplate(config,reduxInfo)},${docResumeTemplate(resume)},${native});
});
</script>""";

String defineBehaviorTemplate({
  String packageName,
  String name,
  Map config,
  String className,
  Map<String, String> mapping,
  String behaviorName,
}) =>
    """<script>
  require(['${_fixModuleName(path.normalize(_moduleForPackage(packageName,mapping:mapping)+'/'+packageName))}','${_fixModuleName(polymerElementPath(mapping))}/polymerize'],function(pkg,behavior) {
  behavior.defineBehavior('${behaviorName}',pkg.${name}.${className},${configTemplate(config,{})});
});
</script>""";

String nativePreloadScript(String tagName, List<String> classPath, String polymerElementPath) => """<script>
 require(['${_fixModuleName(polymerElementPath)}/native_import'],function(util) {
   util.importNative('${tagName}',${classPath.map((s) => '\'${s}\'').join(',')});
 });
</script>""";

String configTemplate(Map config, Map reduxInfo) => (config == null || config.isEmpty)
    ? "null"
    : """{
    observers:[${config['observers'].map((x) => '"${x}"').join(',')}],
    behaviors:[${config['behaviors'].map((x) => 'window.${x}').join(',')}],
    reduxActions:[${config['reduxActions'].map((x) => '"${x}"').join(',')}],
    reduxInfo:{ source : "${reduxInfo['source']??''}", module: "${reduxInfo['module']??''}", name:"${reduxInfo['name']??''}"},
    properties: {
      ${configPropsTemplate(config['properties'])}
    }
  }""";

String docResumeTemplate(HtmlDocResume resume) => resume == null
    ? "null"
    : """{
  props:[${resume.propertyPaths.map((x) => "'${x}'").join(',')}],
  events:[${resume.eventHandlers.map((x) => "'${x}'").join(',')}]
}""";

String configPropsTemplate(Map properties) =>
    properties.keys.map((String propName) => "${propName} : { notify: ${properties[propName]['notify']} ${prop('statePath',properties[propName]['statePath'])}}").join(',\n      ');
String prop(String name, String val) => val != null ? ", ${name} : '${val}'" : "";

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

Future _collectSourcesAndCopyResources(String packageName, Directory dir, List<String> sources, Directory dest) async {
  if (!await dir.exists()) {
    return [];
  }
  //dest = new Directory(path.join(dest.path, packageName));
  await for (FileSystemEntity e in dir.list(recursive: true)) {
    String rel = path.relative(e.path, from: dir.path);

    if (e is File) {
      if (path.extension(e.path) == '.dart' && !path.basename(e.path).startsWith('.')) {
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

    return "${_fixModuleName(_moduleForPackage(m.group(1), mapping: mapping))}/${m.group(1)}";
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

main(List<String> args) async {
  String homePath = user.homeDirPath;
  if (homePath == null) {
    homePath = "/tmp";
  }

  ArgParser parser = new ArgParser()
    ..addSeparator("generic options")
    ..addFlag('emit-output', abbr: 'e', negatable: true, defaultsTo: true, help: 'Should emit output')
    ..addOption('output', abbr: 'o', defaultsTo: 'out', help: 'output directory')
    ..addOption('repo', defaultsTo: path.join(homePath, '.polymerize'), help: 'Repository path (defaults to "\$HOME/.polymerize")')
    ..addOption('source', abbr: 's', defaultsTo: Directory.current.path, help: 'source package path')
    ..addOption('module-format',
        abbr: 'm', allowed: ModuleFormat.values.map((ModuleFormat x) => _formatToString[x]), defaultsTo: _formatToString[ModuleFormat.amd], help: 'module format')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'showHelp')
    ..addCommand(
        'bazel',
        new ArgParser()
          ..addSeparator("bazel build helper")
          ..addOption('base_path', abbr: 'b', help: 'base package path')
          ..addOption("bower-needs", help: 'where to export bower needs')
          ..addOption('export-sdk', help: 'do export sdk')
          ..addOption('export-sdk-html', help: 'do export sdk HTML')
          ..addOption('export-requirejs', help: 'do export requirejs')
          ..addOption('export-require_html', help: 'do export requirehtml')
          ..addOption('source', abbr: 's', allowMultiple: true, help: 'dart source file')
          ..addOption('mapping', abbr: 'M', allowMultiple: true, help: 'external package mapping')
          ..addOption('template_out', abbr: 'T', help: 'html templates rule')
          ..addOption('summary', abbr: 'm', allowMultiple: true, help: 'dart summary file')
          ..addOption('output', abbr: 'o', help: 'output file')
          ..addOption('output_html', help: 'output html wrapper')
          ..addOption('output_summary', abbr: 'x', help: 'output summary file')
          ..addOption('package_name', abbr: 'p', help: 'the package name')
          ..addOption('package_version', abbr: 'v', help: 'the package version'))
    ..addCommand(
        'pub',
        new ArgParser()
          ..addSeparator("pub helper for bazel")
          ..addOption('package', abbr: 'p', help: 'package name')
          ..addOption('version', abbr: 'v', help: 'package version')
          ..addOption('dest', abbr: 'd', help: 'destination')
          ..addOption('pub-host', abbr: 'H', help: 'pub host url'))
    ..addCommand(
        'generate-wrapper',
        new ArgParser()
          ..addSeparator("component wrapper generator")
          ..addOption('component-refs', help: 'Components references yaml')
          ..addOption('dest-path', help: 'Destination path')
          ..addOption('bower-needs-map', allowMultiple: true, help: 'bower needs')
          ..addOption('package-name', abbr: 'p', help: 'dest dart package name')
          ..addFlag('help', help: 'help on generate'))
    ..addCommand(
        'init',
        new ArgParser()
          ..addOption('bower-resolutions', defaultsTo: "bower_resolutions.yaml", abbr: 'B', help: '(Optional) Bower resolutions file')
          ..addOption('dart-bin-path', defaultsTo: findDartSDKHome().path, help: 'dart sdk path')
          ..addOption('rules-version', abbr: 'R', defaultsTo: RULES_VERSION, help: 'Bazel rules version')
          ..addOption('develop', help: "enable polymerize develop mode, with repo home at the given path"))
    ..addCommand(
        "bower",
        new ArgParser()
          ..addOption("resolution-key", abbr: "r", allowMultiple: true)
          ..addOption("resolution-value", abbr: "R", allowMultiple: true)
          ..addOption("use-bower", allowMultiple: true, abbr: 'u', help: 'use bower')
          ..addOption('output', abbr: 'o', help: 'output bower file'))
    ..addCommand("build", new ArgParser()..addOption('package-name', abbr: 'p')..addOption('source', abbr: 's', allowMultiple: true))
    ..addCommand('test')
    ..addCommand(
        'dart_file',
        new ArgParser()
          ..addOption('generate', abbr: 'g')
          ..addOption('summary', abbr: 's', allowMultiple: true)
          ..addOption('input', abbr: 'i')
          ..addOption('dep', abbr: 'd', allowMultiple: true)
          ..addOption('output', abbr: 'o')
          ..addOption('html', abbr: 'h')
          ..addCommand('generate', new ArgParser()..addOption('generate', abbr: 'g')..addOption('input', abbr: 'i')))
    ..addCommand('export_sdk', new ArgParser()..addOption('output', abbr: 'o')..addOption('html', abbr: 'h'));

  // Configure logger
  log.hierarchicalLoggingEnabled = true;
  log.Logger.root.onRecord.listen(new LogPrintHandler());
  log.Logger.root.level = log.Level.INFO;

  ArgResults results = parser.parse(args);

  if (results['help']) {
    print("polymerize <CMD> <options>\n${parser.usage}\n");
    parser.commands.keys.forEach((cmd) {
      print("polymerize ${cmd}\n${parser.commands[cmd].usage}\n");
    });
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

  if (results.command?.name == 'build') {
    //build_cmd.build(results.command['package-name'], results.command['source']);
    return;
  }

  if (results.command?.name == 'export_sdk') {
    await _exportSDK(results.command['output'], results.command['html']);
    return;
  }

  if (results.command?.name == 'dart_file') {
    await ddcBuild(results.command);
    return;
  }

  if (results.command?.name == 'test') {
    //build_cmd.build(results.command['package-name'], results.command['source']);

    Chain.capture(() async {
      String root = path.absolute(results.command.arguments[0]);
      String package = path.absolute(results.command.arguments[1]);
      WorkspaceBuilder builder = await WorkspaceBuilder.create(root, package);
      await builder.generateBuildFiles();
    }, onError: (error, Chain chain) {
      if (error is BuildError) {
        logger.severe("BUILD ERROR : \n${error}", error);
      } else {
        logger.severe("ERROR: ${error}\n AT: ${chain.terse}", error);
      }
    });
    return;
  }

  if (results.command?.name == 'pub') {
    await runPubMode(results.command);
    return;
  }

  if (results.command?.name == 'bower') {
    await runBowerMode(results.command);
    return;
  }

  if (results.command?.name == 'init') {
    runInit(results.command);
    return;
  }

  if (results.command?.name == 'generate-wrapper') {
    if (results.command['help']) {
      print("generate-wrapper usage :\n${parser.commands['generate-wrapper'].usage}");
      return;
    }
    try {
      await new Generator().runGenerateWrapper(results.command);
    } on String catch (error) {
      if (error == "HELP") {
        print("USAGE: ${parser.commands[results.command.name].usage}");
      }
    }
    return;
  }

  Chain.capture(() {
    _buildAll(sourcePath, destPath == null ? null : new Directory(destPath), fmt, repoPath);
  }, onError: (error, Chain chain) {
    if (error is BuildError) {
      logger.severe("BUILD ERROR : \n${error}", error);
    } else {
      logger.severe("ERROR: ${error}\n AT: ${chain.terse}", error);
    }
  });
}

const Map _HEADERS = const {"Content-Type": "application/json"};

Future runInBazelMode(String rootPath, String destPath, String summaryRepoPath, ModuleFormat fmt, ArgResults params) async {
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

  await _buildOne(rootPath, packageName, new Directory(basePath), new Directory(destPath),
      new Directory(path.joinAll([summaryRepoPath, packageName, packageVersion != null ? packageVersion : ""])), [], params['summary'], fmt,
      bazelModeArgs: params);

  if (params['export-sdk'] != null) {
    await _exportSDK(params['export-sdk'], params['export-sdk-html'], fmt);
  }

  if (params['export-requirejs'] != null) {
    await _exportRequireJs(params['export-requirejs'], params['export-require_html']);
  }
}

Future _exportSDK(String dest, String destHTML, [ModuleFormat format = ModuleFormat.amd]) async {
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
