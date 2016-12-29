import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'package:logging/logging.dart';
import 'package:package_resolver/package_resolver.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';
import 'package:glob/glob.dart';

class ImportedData {
  String jsPackageName;
  String jsClassName;
  String dartPackageNameAlias;
  String path;
  String dartPackageURI;

  var descriptor;

  ImportedData(this.jsPackageName, this.jsClassName, this.dartPackageNameAlias, this.path, this.descriptor);
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

    ProcessResult res = await Process.run('node', [(await resolver.resolveUri('package:polymerize/src/js/analyze.js')).toFilePath(), baseDir, relPath], stdoutEncoding: UTF8);

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

    return analysisResult;
  }

  Map<String, String> packageMappings = {};
  String packageName;
  Map<String, String> inOutMap;

  _generateBowerJson(componentsRefs, String destPath) async {
    bowerRefs(componentsRefs) => componentsRefs['components'].map((c) => "\"${c['name']}\" : \"${c['ref']}\"").join(",\n\t");

    await new Directory(destPath).createSync(recursive: true);
    await new File(path.join(destPath, 'bower.json')).writeAsString("""{
  "name": "polymer_dcc",
  "version": "0.0.0",
  "homepage": "https://github.com/dart-lang/polymer-elements",
  "authors": [
    "Polymer.dart Authors <web-ui-dev@dartlang.org>"
  ],
  "private": true,
  "dependencies": {
    ${bowerRefs(componentsRefs)}
  },
  "resolutions": {
    "iron-checked-element-behavior": "2.0-preview",
    "paper-behaviors": "2.0-preview",
    "polymer": "2.0-preview",
    "iron-behaviors": "2.0-preview",
    "iron-a11y-keys-behavior": "2.0-preview",
    "iron-validatable-behavior": "2.0-preview",
    "paper-ripple": "2.0-preview",
    "webcomponentsjs": "v1",
    "iron-meta": "2.0-preview"
  }
}""");
  }

  _installBowerComponents(String destPath) async {
    ProcessResult res = await Process.run('bower', ['install'], workingDirectory: destPath);
    if (res.exitCode != 0) {
      throw res.stderr;
    }
  }

  var _currentBowerRef;
  Map<String, dynamic> _bowerRefsByPath = {};

  _generateMappingFromNeeds(bowerNeeds) async {
    if (bowerNeeds == null) {
      return;
    }

    packageMappings.addAll(new Map.fromIterable(bowerNeeds.map((x) => x.split("=")), key: (x) => x[0], value: (x) => x[1]));
  }

  _generateWrappers(String dartPackageName, componentsRefs, Map mappings, String destPath) async {
    await Future.wait(componentsRefs['components'].map((comp) => _generateWrapper(dartPackageName, comp, componentsRefs, mappings, destPath)));

    //print("Resulting mappings :${packageMappings}");
    print("Start writing results: \n");

    String libPath = path.join(destPath, 'lib');
    for (String p in analysisResults.keys) {
      relPath = p;
      analysisResult = analysisResults[p];
      _currentBowerRef = _bowerRefsByPath[p];

      bool hadElements = await _generateElements(libPath);
      bool hadBehaviors = await _generateBehaviors(libPath);
      if (!hadElements && !hadBehaviors) {
        await _writeDart(
            libPath,
            """
import 'package:polymer_element/polymer_element.dart' show BowerImport;

${importBehaviors(relPath,'_',{})}

/**
 **/
@BowerImport(ref:'${_currentBowerRef['ref']}',import:"${relPath}",name:'${_currentBowerRef['name']}')
class _ {

}
""");
      }
    }
  }

  Future<List<String>> _enlistFile(String destPath, String componentName, List<String> includes, List<String> excludes) async {
    String from = path.join(destPath, componentName);
    Iterable<Glob> includeGlobs = ((includes ?? ["${componentName}.html"]) as List).map((pat) => new Glob(pat, recursive: false));
    Iterable<Glob> excludeGlobs = ((excludes ?? []) as List).map((pat) => new Glob(pat, recursive: false));
    List result = [];
    await for (FileSystemEntity entry in new Directory(from).list(recursive: true)) {
      if (entry is File) {
        String rel = path.relative(entry.path, from: from);

        if (includeGlobs.any((i) => i.matches(rel)) && excludeGlobs.every((e) => !e.matches(rel))) result.add("${componentName}/${rel}");
      }
    }
    return result;
  }

  _generateWrapper(String dartPackageName, component, componentsRefs, Map mappings, String destPath) async {
    String componentName = component['name'];
    String componentRef = component['ref'];

    String compDir = path.join(destPath, "bower_components");

    List paths = component['paths'] ?? await _enlistFile(compDir, componentName, component['includes'], component['excludes']);

    if (paths.isEmpty) {
      throw "No files found for ${destPath}/${componentName}, please specify explicit `path` list in component entry or appropriate `includes` and `excludes` pattern lists";
    }

    //print(
    //    "[${componentName}]: ${component['includes']} - ${component['excludes']} => ${paths}");

    packageName = dartPackageName;
    inOutMap = mappings ?? {};

    await Future.wait(paths.map((p) async {
      // Read and analyze the source doc
      //print("anal ${compDir}  ${p}");
      var res = await _analyze(p, compDir);
      //print("RES: ${res}");
      _bowerRefsByPath[p] = component;

      var mineBehaviors = res['behaviors'].values.where((x) => x['main_file']);
      var mineElements = res['elements'].values.where((x) => x['main_file']);

      inOutMap[p] = _outputFileFor(p);

      mineBehaviors.forEach((b) {
        // Fill the map
        packageMappings[b['name']] = 'package:${packageName}/${inOutMap[p]}';
        new Logger("analyzing phase").info("Analyzed ${b['name']}");
      });

      mineElements.forEach((b) {
        // Fill the map
        packageMappings[b['name']] = 'package:${packageName}/${inOutMap[p]}';
        new Logger("analyzing phase").info("Analyzed ${b['name']}");
      });

      if (mineBehaviors.isEmpty && mineElements.isEmpty) {
        new Logger("analyzing phase").warning("${p} was empty");
      }
    }));
  }

  _outputFileFor(String p) => path.basenameWithoutExtension(p).replaceAll("-", "_") + ".dart";

  runGenerateWrapper(ArgResults params) async {
    // 1. legge il components.yaml
    // 2. genera il bower.json
    // 3. fa il bower install
    // 4. legge i bower_needs generati da altre lib
    // 5. genera i wrappers

    String componentRefsPath = params['component-refs'];
    String destPath = params['dest-path'];
    Map bowerNeeds = params['bower-needs-map'];
    String dartPackageName = params['package-name'];

    var componentsRefs = loadYaml(await new File(componentRefsPath).readAsString());

    //print("Genrating wrappers with : ${componentsRefs['components'].map((c)=>c['name']).join(',')}");

    await _generateBowerJson(componentsRefs, destPath);

    await _installBowerComponents(destPath);

    var mappings = await _generateMappingFromNeeds(bowerNeeds);

    await _generateWrappers(dartPackageName, componentsRefs, mappings, destPath);
  }

  _generateElements(String destPath) async {
    Map<String, Map> elements = analysisResult['elements'];
    if (elements == null || elements.isEmpty) return false;
    bool found = false;
    await Future.wait(elements.keys.map((name) async {
      var descr = elements[name];
      if (!descr['main_file']) return;
      found = true;
      String res = _generateElement(name, _currentBowerRef, descr);
      await _writeDart(destPath, res);
    }));

    return found;
  }

  _generateBehaviors(String destPath) async {
    Map<String, Map> elements = analysisResult['behaviors'];
    if (elements == null || elements.isEmpty) return false;
    bool found = false;
    await Future.wait(elements.keys.map((name) async {
      var descr = elements[name];
      if (!descr['main_file']) return;
      found = true;
      String res = _generateBehavior(name, _currentBowerRef, descr);
      await _writeDart(destPath, res);
    }));

    return found;
  }

  _writeDart(String destPath, String content) async {
    String p = path.join(destPath, inOutMap[relPath]);
    await new Directory(path.dirname(p)).create(recursive: true);
    await new File(p).writeAsString(content);
    print("Wrote ${p}");
  }

  _generateElement(String name, var bowerRef, Map descr) {
    _importPrefixes = {};
    return """
@JS('PolymerElements')
library ${name};
import 'dart:html';
import 'package:js/js.dart';
import 'package:js/js_util.dart';

import 'package:polymer_element/polymer_element.dart';
${importBehaviors(relPath,name,descr)}

${generateComment(descr['description'])}

//@JS('PaperButton')
@PolymerRegister('${descr['name']}',native:true)
@BowerImport(ref:'${bowerRef['ref']}',import:"${relPath}",name:'${bowerRef['name']}')
abstract class ${name} extends PolymerElement ${withBehaviors(relPath,name,descr)} {
${generateProperties(relPath,name,descr,descr['properties'])}
}
""";
  }

  _generateBehavior(String name, var bowerRef, Map descr) {
    _importPrefixes = {};
    return """
@JS('PolymerElements')
library ${name};
import 'dart:html';
import 'package:js/js.dart';
import 'package:js/js_util.dart';

import 'package:polymer_element/polymer_element.dart';
${importBehaviors(relPath,name,descr)}

${generateComment(descr['description'])}

@BowerImport(ref:'${bowerRef['ref']}',import:"${relPath}",name:'${bowerRef['name']}')
abstract class ${name.split('.').last} ${withBehaviors(relPath,name,descr,keyword:'implements')} {
${generateProperties(relPath,name,descr,descr['properties'])}
}

""";
  }

  withBehaviors(String relPath, String name, Map descr, {String keyword: 'with'}) {
    List behaviors = descr['behaviors'];
    if (behaviors == null || behaviors.isEmpty) {
      return "";
    }

    return "${keyword} " + behaviors.map((behavior) => withBehavior(relPath, name, descr, behavior)).join(',');
  }

  withBehavior(String relPath, String name, Map descr, Map behavior) {
    String n = behavior['name'];
    String prefix = _importPrefixes[n];
    int p = n.lastIndexOf(".");
    if (p >= 0) {
      n = n.substring(p + 1);
    }

    return "${prefix}.${n}";
  }

  indents(int i, String s) => ((p, s) => s.split("\n").map((x) => p + x).join("\n"))(UTF8.decode(new List.filled(i, UTF8.encode(" ").first)), s);

  generateComment(String comment, {int indent: 0}) => indents(indent, "/**\n * " + comment.split(new RegExp("\n+")).join("\n * ") + "\n */");

  Map<String, String> _importPrefixes;

  String _dartType(String jsType) => const {'string': 'String', 'boolean': 'bool', 'Object': '', 'number': 'num', 'Array': 'List', 'HTMLElement': 'HtmlElement'}[jsType] ?? jsType;

  Iterable _importedThings(Map descr) sync* {
    if (analysisResult['elements'] != null) {
      yield* analysisResult['elements'].values.where((x) => !x['main_file']);
    }

    if (analysisResult['behaviors'] != null) {
      yield* analysisResult['behaviors'].values.where((x) => !x['main_file']);
    }

    Set<String> names = new Set.from(analysisResult['behaviors'].keys);

    // For behaviors that are used but not analyzed (TODO: how to do the same with elements?)
    yield* (descr['behaviors'] ?? []).where((x) => !names.contains(x['name']));
  }

  importBehaviors(String relPath, String name, Map descr) => _importedThings(descr).map((b) {
        String prefix = "imp${_importPrefixes.length}";
        _importPrefixes[b['name']] = prefix;
        return 'import \'${resolveImport(b)}\' as ${prefix};';
      }).join('\n');

  generateProperties(String relPath, String name, Map descr, Map properties) {
    if (properties == null) {
      return "";
    }

    return properties.values.map((p) => generateProperty(relPath, name, descr, p)).join("\n");
  }

  generateProperty(String relPath, String name, Map descr, Map prop) {
    Map overrides = _currentBowerRef['overrides'] ?? {};
    //print("OVERRIDES: ${overrides} , ${name}");
    if (overrides.containsKey(prop['name'])) {
      return "${generateComment(prop['description'], indent: 2)}\n${overrides[prop['name']].join('\n')}";
    } else {
      return """
${generateComment(prop['description'], indent: 2)}
  ${_dartType(prop['type'])} get ${prop['name']};
  set ${prop['name']}(${_dartType(prop['type'])} value);
""";
    }
  }
}
