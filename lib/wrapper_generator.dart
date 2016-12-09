import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'package:package_resolver/package_resolver.dart';
import 'package:path/path.dart' as path;

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

  String resolveImport(var descr) => packageMappings[descr['name']];

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
    print("Reading ${src}");
    PackageResolver resolver = PackageResolver.current;
    String relPath = path.relative(src, from: baseDir);

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
    var analysisResult = JSON.decode(out);
    //var relPath = "src/${relPath}";

    analysisResults[relPath] = analysisResult;

    return analysisResult;
  }

  Map<String,String> packageMappings = {};
  String packageName;
  Map<String,String> inOutMap;

  runGenerateWrapper(ArgResults params) async {

    inOutMap = new Map.fromIterables(params['file-path'], params['output-path']);
    packageName =params['package-name'];

    //new res.Resource('package:polymerize/src/js/analyze.js');
    //print("FILE TO PROCESS: ${params['file-path']}");
    await Future.wait(params['file-path'].map((p) async {
      // Read and analyze the source doc
      var res= await _analyze(p, params['base-dir']);

      var mineBehaviors = res['behaviors'].values.where((x) => x['main_file']);
      var mineElements = res['elements'].values.where((x) => x['main_file']);

      mineBehaviors.forEach((b) {
        // Fill the map
        packageMappings[b['name']] = 'package:${packageName}/${inOutMap[p]}';

      });

      mineElements.forEach((b) {
        // Fill the map
        packageMappings[b['name']] = 'package:${packageName}/${inOutMap[p]}';

      });

    }));

    print("Resulting mappings :${packageMappings}");

    analysisResults.forEach((p, res) {
      relPath = p;
      analysisResult = res;

      generate_elements();
      generate_behaviors();
    });
//print("RES = ${result}");
  }

  generate_elements() {
    Map<String, Map> elements = analysisResult['elements'];
    if (elements == null) return;
    elements.forEach((name, descr) {
      if (!descr['main_file']) return;
      String res = generate_element(name, descr);
      print(res);
    });
  }

  generate_behaviors() {
    Map<String, Map> elements = analysisResult['behaviors'];
    if (elements == null) return;
    elements.forEach((name, descr) {
      if (!descr['main_file']) return;
      String res = generate_behavior(name, descr);
      print(res);
    });
  }

  generate_element(String name, Map descr) {
    return """
@JS('PolymerElements')
library ${name};
import 'dart:html';
import 'package:js/js.dart';
import 'package:polymer_element/polymer_element.dart';
${importBehaviors(relPath,name,descr)}

${generateComment(descr['description'])}

abstract class PaperButtonBehavior {
  bool get raised;
  set raised(bool value);
}

//@JS('PaperButton')
@PolymerRegister('${descr['name']}',template:'${relPath}',native:true)
class ${name} extends PolymerElement ${withBehaviors(relPath,name,descr)} {
${generateProperties(relPath,name,descr,descr['properties'])}
}
""";
  }

  generate_behavior(String name, Map descr) {
    return """
@JS('PolymerElements')
library ${name};
import 'dart:html';
import 'package:js/js.dart';
import 'package:polymer_element/polymer_element.dart';
${importBehaviors(relPath,name,descr)}

${generateComment(descr['description'])}

@PolymerRegister('${descr['name']}',template:'${relPath}',native:true,behavior:true)
abstract class ${name}  ${withBehaviors(relPath,name,descr)} {
${generateProperties(relPath,name,descr,descr['properties'])}
}

""";
  }

  withBehaviors(String relPath, String name, Map descr) {
    List behaviors = descr['behaviors'];
    if (behaviors == null) {
      return "";
    }

    return "with " +
        behaviors
            .map((behavior) => withBehavior(relPath, name, descr, behavior))
            .join(',');
  }

  withBehavior(String relPath, String name, Map descr, Map behavior) =>
      behavior['name'];

  indents(int i, String s) =>
      ((p, s) => s.split("\n").map((x) => p + x).join("\n"))(
          UTF8.decode(new List.filled(i, UTF8.encode(" ").first)), s);

  generateComment(String comment, {int indent: 0}) => indents(indent,
      "/**\n * " + comment.split(new RegExp("\n+")).join("\n * ") + "\n */");

  importBehaviors(String relPath, String name, Map descr) => descr['behaviors']
      .map((b) => 'import \'${resolveImport(b)}\';')
      .join('\n');

  generateProperties(String relPath, String name, Map descr, Map properties) {
    if (properties == null) {
      return "";
    }

    return properties.values
        .map((p) => generateProperty(relPath, name, descr, p))
        .join("\n");
  }

  generateProperty(String relPath, String name, Map descr, Map prop) => """
${generateComment(prop['description'],indent:2)}
  ${prop['type']} get ${prop['name']}();
  void set ${prop['name']}(${prop['type']} value);
""";
}
