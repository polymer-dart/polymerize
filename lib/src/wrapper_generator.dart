import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'package:logging/logging.dart';
import 'package:package_resolver/package_resolver.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';
import 'package:glob/glob.dart';

Logger _logger = new Logger('wrapper_generator');

class ImportedData {
  String jsPackageName;
  String jsClassName;
  String dartPackageNameAlias;
  String path;
  String dartPackageURI;

  var descriptor;

  ImportedData(this.jsPackageName, this.jsClassName, this.dartPackageNameAlias,
      this.path, this.descriptor);
}

class Generator {
  /**
   * All results
   */
  Map<String, dynamic> analysisResults = {};
  String relPath;
  var analysisResult;
  var descriptor;

  Map behaviors = <String, ImportedData>{};

  String resolveImport(var descr) =>
      packageMappings[descr['name']] ??
      (x) {
        throw "Cannot resolve ${x}";
      }(descr['name']);

  String resolveImportOld(var descr) {
    String behaviorName = descr['name'];
    String file = descr['sourceRange']['file'];
    ImportedData data = behaviors.putIfAbsent(behaviorName, () {
      var p = behaviorName.lastIndexOf(".");
      String prefix = behaviorName.substring(0, p);
      String name = behaviorName.substring(p + 1);

      String package = prefix.replaceAll(".", "_");
      return new ImportedData(prefix, name, package, file, descr);
    });

    return data.dartPackageURI;
  }

  /**
   * Analyzing a file
   */
  Future _analyze(String src, String baseDir) async {
    PackageResolver resolver = PackageResolver.current;
    String relPath = src;

    ProcessResult res = await Process.run(
        'node',
        [
          (await resolver.resolveUri('package:polymerize/src/js/analyze.js'))
              .toFilePath(),
          baseDir,
          relPath
        ],
        stdoutEncoding: UTF8);

    if (res.exitCode != 0) {
      print(res.stderr);
      throw "Error while reading ${relPath}";
    }

    var out = res.stdout;
    //print("res.stdout : ${out}");
    var analysisResult;
    try {
      analysisResult = JSON.decode(out);
    } catch (e) {
      throw "Error while analizing ${src} from ${baseDir} : ${e},${out}";
    }
    //var relPath = "src/${relPath}";

    analysisResults[relPath] = analysisResult;
    _logger.finest("Analyzed ${analysisResults.length} files");

    return analysisResult;
  }

  Map<String, String> packageMappings = {};
  String packageName;
  Map<String, String> inOutMap;

  _generateBowerJson(componentsRefs, String destPath) async {
    await new Directory(destPath).createSync(recursive: true);
    await new File(path.join(destPath, 'bower.json'))
        .writeAsString(JSON.encode({
      "name": "generated_elements",
      "version": "0.0.0",
      "homepage": "https://dart-polymer.com",
      "authors": ["Dart-Polymer <info@dart-polymer.com>"],
      "private": true,
      "dependencies": new Map.fromIterable(componentsRefs['components'],
          key: (x) => x['name'], value: (x) => x['ref']),
      "resolutions": new Map()..addAll(componentsRefs['resolutions'])
    }));
    _logger.info("Created `bower.json`");
  }

  _installBowerComponents(String destPath) async {
    _logger.info("Downloading bower components");
    ProcessResult res =
        await Process.run('bower', ['install'], workingDirectory: destPath);
    if (res.exitCode != 0) {
      _logger.severe(
          "Error downloading bower components, try running `bower install` in ${destPath}, and eventually add a `resolutions` section to the component file");
      throw res.stderr;
    }
  }

  var _currentBowerRef;
  Map<String, dynamic> _bowerRefsByPath = {};

  Future _generateMappingFromNeeds(bowerNeeds) async {
    if (bowerNeeds == null) {
      return;
    }

    packageMappings.addAll(new Map.fromIterable(
        bowerNeeds.map((x) => x.split("=")),
        key: (x) => x[0],
        value: (x) => x[1]));

    //print("Using mappings : ${packageMappings} from ${bowerNeeds}");
  }

  _generateWrappers(
      String dartPackageName, componentsRefs, String destPath) async {
    inOutMap = <String, String>{};
    for (Map comp in componentsRefs['components']) {
      await _analyzeComponent(dartPackageName, comp, componentsRefs, destPath);
    }

    //print("Resulting mappings :${packageMappings}");
    _logger.info(
        "Start writing results for ${analysisResults.keys.length} files: \n");
    List<String> paths = new List.from(analysisResults.keys);
    _logger.finest("Files to generate [${paths.length}] : ${paths}");

    String libPath = path.join(destPath, 'lib');
    for (String p in paths) {
      relPath = p;
      _logger.fine("Processing ${relPath}");
      analysisResult = analysisResults[p];
      _currentBowerRef = _bowerRefsByPath[p];

      try {
        bool hadElements =
            await _generateElements(componentsRefs['namespace'], libPath);
        bool hadBehaviors =
            await _generateBehaviors(componentsRefs['namespace'], libPath);
        if (!hadElements && !hadBehaviors) {
          await _writeDart(
              libPath,
              """
import 'package:polymer_element/polymer_element.dart' show BowerImport;

${importBehaviors(relPath,'_')}

/**
 **/
@BowerImport(ref:'${_currentBowerRef['ref']}',import:"${relPath}",name:'${_currentBowerRef['name']}')
class _ {

}
""");
        }
      } catch (error, stack) {
        _logger.severe("While processing ${p}", error, stack);
      }
    }
  }

  Future<List<String>> _enlistFile(String destPath, String componentName,
      List<String> includes, List<String> excludes) async {
    String from = path.join(destPath, componentName);
    Iterable<Glob> includeGlobs = (includes ?? ["${componentName}.html"])
        .map((pat) => new Glob(pat, recursive: false));
    Iterable<Glob> excludeGlobs =
        (excludes ?? []).map((pat) => new Glob(pat, recursive: false));
    List result = [];
    await for (FileSystemEntity entry
        in new Directory(from).list(recursive: true)) {
      if (entry is File) {
        String rel = path.relative(entry.path, from: from);

        if (includeGlobs.any((i) => i.matches(rel)) &&
            excludeGlobs.every((e) => !e.matches(rel)))
          result.add("${componentName}/${rel}");
      }
    }
    return result;
  }

  _analyzeComponent(String dartPackageName, component, componentsRefs,
      String destPath) async {
    String componentName = component['name'];
    //String componentRef = component['ref'];

    String compDir = path.join(destPath, "bower_components");

    List paths = component['paths'] ??
        await _enlistFile(compDir, componentName, component['includes'],
            component['excludes']);

    if (paths.isEmpty) {
      throw "No files found for ${destPath}/${componentName}, please specify explicit `path` list in component entry or appropriate `includes` and `excludes` pattern lists";
    }

    //print(
    //    "[${componentName}]: ${component['includes']} - ${component['excludes']} => ${paths}");

    packageName = dartPackageName;

    for (String p in paths) {
      // Read and analyze the source doc
      //print("anal ${compDir}  ${p}");

      _logger.info("Reading ${p}");
      var res = await _analyze(p, compDir);
      //print("RES: ${res}");
      _bowerRefsByPath[p] = component;

      var mineBehaviors = res['behaviors'].values.where((x) => x['main_file']);
      var mineElements = res['elements'].values.where((x) => x['main_file']);

      inOutMap[p] = _outputFileFor(p);

      mineBehaviors.forEach((b) {
        // Fill the map
        packageMappings[b['name']] = 'package:${packageName}/${inOutMap[p]}';
        _logger.info("Found ${b['name']}");
      });

      mineElements.forEach((b) {
        // Fill the map
        packageMappings[b['name']] = 'package:${packageName}/${inOutMap[p]}';
        _logger.info("Found ${b['name']}");
      });

      if (mineBehaviors.isEmpty && mineElements.isEmpty) {
        _logger.warning("${p} contains no elements nor behaviors ...");
      }
    }
  }

  _outputFileFor(String p) =>
      path.basenameWithoutExtension(p).replaceAll("-", "_") + ".dart";

  runGenerateWrapper(ArgResults params) async {
    // 1. legge il components.yaml
    // 2. genera il bower.json
    // 3. fa il bower install
    // 4. legge i bower_needs generati da altre lib
    // 5. genera i wrappers

    String componentRefsPath = params['component-refs'];
    String destPath = params['dest-path'];
    List bowerNeeds = params['bower-needs-map'];

    if (componentRefsPath == null || destPath == null) {
      throw "HELP";
    }

    var componentsRefs =
        loadYaml(await new File(componentRefsPath).readAsString());

    String dartPackageName =
        params['package-name'] ?? componentsRefs['package-name'];

    //print("Genrating wrappers with : ${componentsRefs['components'].map((c)=>c['name']).join(',')}");

    await _generateBowerJson(componentsRefs, destPath);

    await _installBowerComponents(destPath);

    await _generateMappingFromNeeds(bowerNeeds);
    if ((componentsRefs as Map).containsKey('externals')) {
      packageMappings.addAll(componentsRefs['externals']);
    }

    _logger.info("Generating components");
    await _generateWrappers(dartPackageName, componentsRefs, destPath);
  }

  _generateElements(String namespace, String destPath) async {
    Map<String, Map> elements = analysisResult['elements'];
    if (elements == null || elements.isEmpty) return false;
    bool found = false;
    for (String name in elements.keys) {
      var descr = elements[name];
      if (!descr['main_file']) continue;
      found = true;
      await _writeDart(
          destPath, _generateElement(namespace, name, _currentBowerRef, descr));
    }

    return found;
  }

  _generateBehaviors(String namespace, String destPath) async {
    Map<String, Map> elements = analysisResult['behaviors'];
    if (elements == null || elements.isEmpty) return false;
    bool found = false;

    // Filter only elements
    elements = new Map.fromIterable(
        elements.keys.where((x) => elements[x]['main_file']),
        value: (x) => elements[x]);
    if (elements.isEmpty) return false;

    String res = _generateBehaviorHeader(
        namespace, elements.keys.first, _currentBowerRef);
    for (String name in elements.keys) {
      var descr = elements[name];
      res += _generateBehavior(namespace, name, _currentBowerRef, descr);
    }

    await _writeDart(destPath, res);
    return true;
  }

  int _generatedFilesCount = 0;

  _writeDart(String destPath, String content) async {
    String p = path.join(destPath, inOutMap[relPath]);
    await new Directory(path.dirname(p)).create(recursive: true);
    await new File(p).writeAsString(content);
    _logger.info("Wrote ${p} [${++_generatedFilesCount}]");
  }

  _generateElement(String namespace, String name, var bowerRef, Map descr) {
    _importPrefixes = {};
    return """
@JS('${namespace}')
library ${name};
import 'package:html5/html.dart';
import 'package:js/js.dart';
import 'package:js/js_util.dart';

import 'package:polymer_element/polymer_element.dart';
${importBehaviors(relPath,name)}

${generateComment(descr['description'])}

@JS('${name}')
@PolymerRegister('${descr['name']}',native:true)
@BowerImport(ref:'${bowerRef['ref']}',import:"${relPath}",name:'${bowerRef['name']}')
abstract class ${name} extends PolymerElement ${withBehaviors(relPath,name,descr)} {
${generateProperties(relPath,name,descr,descr['properties'])}
${generateMethods(relPath,name,descr,descr['methods'])}
}
""";
  }

  _generateBehavior(String namespace, String name, var bowerRef, Map descr) {
    return """
${generateComment(descr['description'])}

@BowerImport(ref:'${bowerRef['ref']}',import:"${relPath}",name:'${bowerRef['name']}')
@JS('${name.split('.').last}')
abstract class ${name.split('.').last} ${withBehaviors(relPath,name,descr,keyword:'implements')} {
${generateProperties(relPath,name,descr,descr['properties'])}
${generateMethods(relPath,name,descr,descr['methods'])}
}

""";
  }

  _generateBehaviorHeader(String namespace, String name, var bowerRef) {
    _importPrefixes = {};
    return """
@JS('${(name){
  List x = name.split('.');
  return x.sublist(0,x.length-1).join('.');
}(name)}')
library ${name};
import 'package:html5/html.dart';
import 'package:js/js.dart';
import 'package:js/js_util.dart';

import 'package:polymer_element/polymer_element.dart';
${importBehaviors(relPath,name)}

""";
  }

  withBehaviors(String relPath, String name, Map descr,
      {String keyword: 'implements'}) {
    List behaviors = descr['behaviors'];
    if (behaviors == null || behaviors.isEmpty) {
      return "";
    }

    return "${keyword} " +
        behaviors
            .map((behavior) => withBehavior(relPath, name, descr, behavior))
            .join(',');
  }

  withBehavior(String relPath, String name, Map descr, Map behavior) {
    String n = behavior['name'];
    String prefix = _importPrefixes[n];
    int p = n.lastIndexOf(".");
    if (p >= 0) {
      n = n.substring(p + 1);
    }

    return (prefix != null) ? "${prefix}.${n}" : n;
  }

  indents(int i, String s) =>
      ((p, s) => s.split("\n").map((x) => p + x).join("\n"))(
          UTF8.decode(new List.filled(i, UTF8.encode(" ").first)), s);

  generateComment(String comment, {int indent: 0}) => indents(indent,
      "/**\n * " + comment.split(new RegExp("\n+")).join("\n * ") + "\n */");

  Map<String, String> _importPrefixes;

  String _dartType(String jsType) =>
      const {
        'string': 'String',
        'boolean': 'bool',
        'Object': '',
        'number': 'num',
        'Array': 'List',
      }[jsType] ??
      jsType;

  Iterable _importedThings() sync* {
    // Defined behavior names
    Set<String> names = new Set.from((analysisResult['behaviors'] ?? {})
        .keys
        .where((x) => analysisResult['behaviors'][x]['main_file']));

    if (analysisResult['elements'] != null) {
      for (String k in analysisResult['elements'].keys) {
        Map v = analysisResult['elements'][k];
        if (!v['main_file'])
          yield v;
        else if ((v['behaviors'] ?? []).isNotEmpty)
          yield* v['behaviors'].where((x) => !names.contains(x['name']));
      }
    }

    if (analysisResult['behaviors'] != null) {
      for (String k in analysisResult['behaviors'].keys) {
        Map v = analysisResult['behaviors'][k];
        if (!v['main_file'])
          yield v;
        else if ((v['behaviors'] ?? []).isNotEmpty)
          yield* v['behaviors'].where((x) => !names.contains(x['name']));
      }
    }
  }

  importBehaviors(String relPath, String name) => _importedThings().map((b) {
        String prefix = "imp${_importPrefixes.length}";
        _importPrefixes[b['name']] = prefix;
        return 'import \'${resolveImport(b)}\' as ${prefix};';
      }).join('\n');

  generateProperties(String relPath, String name, Map descr, Map properties) {
    if (properties == null) {
      return "";
    }

    return properties.values
        .map((p) => generateProperty(relPath, name, descr, p))
        .join("\n");
  }

  generateMethods(String relPath, String name, Map descr, Map methods) {
    if (methods == null) {
      return "";
    }

    return methods.values
        .map((p) => generateMethod(relPath, name, descr, p))
        .join("\n");
  }

  generateProperty(String relPath, String name, Map descr, Map prop) {
    Map overrides = (_currentBowerRef['overrides'] ?? {})[name] ?? {};
    //print("OVERRIDES: ${overrides} , ${name}");
    if (overrides.containsKey(prop['name'])) {
      return "${generateComment(prop['description'], indent: 2)}\n${overrides[prop['name']].join('\n')}";
    } else {
      return """
${generateComment(prop['description'], indent: 2)}
  external ${_dartType(prop['type'])} get ${prop['name']};
  external set ${prop['name']}(${_dartType(prop['type'])} value);
""";
    }
  }

  generateMethod(String relPath, String name, Map descr, Map method) {
    Map overrides = (_currentBowerRef['overrides'] ?? {})[name] ?? {};
    //print("OVERRIDES: ${overrides} , ${name}");
    if (overrides.containsKey(method['name'])) {
      return "${generateComment(method['description'], indent: 2)}\n${overrides[method['name']].join('\n')}";
    } else {
      return """
${generateComment(method['description'], indent: 2)}
  external ${method['isVoid']?'void':_dartType(method['type']??'')} ${method['name']}(${generateArgs(method['args'])});
""";
    }
  }

  generateArgs(List args) =>
      args.map((x) => "${_dartType(x['type'])} ${x['name']}").join(',');
}
