import 'package:dev_compiler/src/analyzer/context.dart';
import 'package:dev_compiler/src/compiler/compiler.dart';
import 'package:analyzer/src/summary/package_bundle_reader.dart';
import 'package:path/path.dart' as path;
import 'package:analyzer/src/generated/source.dart';
import 'package:build/src/package_graph/package_graph.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:stack_trace/stack_trace.dart';
import 'package:resource/resource.dart';

const String DEFAULT_TEMPLATE = """
<html>
<head>
<script>
'use strict';
</script>
@IMPORT_SCRIPTS@
@BOOTSTRAP@
</head>
<body>
</body>
</html>
""";

Future _buildAll(String rootPath, Directory dest, String mainModule) async {
  /*if (await dest.exists()) {
    await dest.delete(recursive:true);
  }*/

  if (!await dest.exists()) await dest.create(recursive: true);

  PackageGraph packageGraph = new PackageGraph.forPath(rootPath);

  // Build Packages in referse order

  Map summaries = {};
  await _buildPackage(rootPath, packageGraph.root, summaries, dest, ".repo");

  // Build index.html

  File index = new File(path.join(dest.path, "index.html"));

  // The order is irrelevant ---
  List<String> scripts = summaries.keys
      .map((PackageNode n) => "<script src='${n.name}.js'></script>");

  await _copyResource("package:dev_compiler/runtime/dart_sdk.js",
      path.join(dest.path, "dart_sdk.js"));
  await _copyResource("package:dev_compiler/runtime/dart_library.js",
      path.join(dest.path, "dart_library.js"));

  // If an index.html template exists use it

  File templateFile = new File(path.join(rootPath,"web", "index.html"));

  String indexTemplate;
  if (await templateFile.exists()) {
    indexTemplate = await templateFile.readAsString();
  } else {
    indexTemplate = DEFAULT_TEMPLATE;
  }

  // Replace
  indexTemplate = indexTemplate.replaceAllMapped(
      new RegExp("@([^@]+)@"),
      (Match m) => {
            "ENTRY_POINT": mainModule,
            "IMPORT_SCRIPTS": """<script src='dart_library.js'></script>
<script src='dart_sdk.js'></script>
${scripts.join('\n')}""",
            "ROOT_PACKAGE_NAME": packageGraph.root.name,
            "BOOTSTRAP": """<script>
	// Start the main in module '${mainModule}'
	dart_library.start('${packageGraph.root.name}','${mainModule}');
</script>"""
          }[m.group(1)]);

  return index.writeAsString(indexTemplate);
}

Future _copyResource(String res, String dest) async {
  Resource rsx = new Resource(res);
  String content = await rsx.readAsString();
  return new File(dest).writeAsString(content);
}

Future<List<String>> _buildPackage(
    String rootPath,
    PackageNode node,
    Map<PackageNode, List<String>> summaries,
    Directory dest,
    String summaryRepoPath) async {
  List<String> result;

  result = summaries[node];
  if (result != null) {
    return result;
  }

  // Build this package

  Set deps = new Set();
  for (PackageNode dep in node.dependencies) {
    deps.addAll(
        await _buildPackage(rootPath, dep, summaries, dest, summaryRepoPath));
  }

  print("Building ${node.name}");

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
      node.dependencyType == PackageDependencyType.pub));

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
    bool useRepo) async {
  File repo_smap =
      new File(path.join(summaryDest.path, "${packageName}.js.map"));
  File sum = new File(path.join(summaryDest.path, "${packageName}.sum"));
  File repo_js = new File(path.join(summaryDest.path, "${packageName}.js"));
  File smap = new File(path.join(dest.path, "${packageName}.js.map"));

  File js = new File(path.join(dest.path, "${packageName}.js"));


  // Collect sources from filesystem
  List<String> sources = [];

  if (!await summaryDest.exists()) {
    await summaryDest.create(recursive: true);
  }

  await _collectSourcesAndCopyResources(packageName,
      new Directory(path.join(location.path, "lib")), sources, dest);
  print("  Collected : ${sources}");
  print("  Summaries : ${summaries}");

  // If use repo (after collect and copy)
  if (useRepo && await repo_js.exists() && await repo_smap.exists()) {
    // Use it, do not build it again
    await repo_js.copy(js.path);
    await repo_smap.copy(smap.path);
    print("CACHED : ${sum.path}");
    return sum.path;
  }

  ModuleCompiler moduleCompiler = new ModuleCompiler(new AnalyzerOptions(
      packageRoot: path.join(rootPath, "packages"), summaryPaths: summaries));
  CompilerOptions compilerOptions = new CompilerOptions();

  BuildUnit bu = new BuildUnit(packageName, ".", sources,
      (source) => _moduleForLibrary(dest.path, source));

  JSModuleFile res = moduleCompiler.compile(bu, compilerOptions);
  if (!res.isValid) {
    throw new BuildError(res.errors);
  }

  // Write outputs

  await js.writeAsString(res.code);
  await js.copy(repo_js.path);

  // Write source map

  await smap.writeAsString(JSON.encode(res.placeSourceMap(smap.path)));
  await smap.copy(repo_smap.path);

  // Write summary

  //File sum = new File(path.join(summaryDest.path, "${packageName}.sum"));
  await sum.writeAsBytes(res.summaryBytes);

  print("BUILT : ${sum.path}");

  return sum.path;
}

class BuildError {
  List messages;

  BuildError(this.messages);

  toString() => messages.join("\n");
}

Future _collectSourcesAndCopyResources(String packageName, Directory dir, List<String> sources,
    Directory dest) async {
  if (!await dir.exists()) {
    return [];
  }
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

String _moduleForLibrary(String moduleRoot, Source source) {
  if (source is InSummarySource) {
    //print ("SOURCES : ${source.summaryPath} , ${source.fullName} , ${moduleRoot}");

    RegExp re = new RegExp(r"^package:([^/]+).*$");
    Match m = re.matchAsPrefix(source.fullName);
    if (m == null) {
      throw "Source should be in package format :${source.fullName}";
    }

    return m.group(1);
  }

  throw 'Imported file "${source.uri}" was not found as a summary or source '
      'file. Please pass in either the summary or the source file '
      'for this import.';
}

main(List<String> args) {
  if (args == null || args.length != 3) {
    print(
        "USAGE : dart devc_builder main_source_package_path output_path mainpackage_file_containing_main");
    return;
  }
  Chain.capture(() {
    _buildAll(args[0], new Directory(args[1]), args[2]);
  }, onError: (error, Chain chain) {
    if (error is BuildError) {
      print("BUILD ERROR : \n: ${error}");
    } else {
      print("ERROR: ${error}\n AT: ${chain.terse}");
    }
  });
}
