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

Future _buildAll(String rootPath, Directory dest,String mainModule) async {
  /*if (await dest.exists()) {
    await dest.delete(recursive:true);
  }*/

  if (!await dest.exists()) await dest.create(recursive: true);

  PackageGraph packageGraph = new PackageGraph.forPath(rootPath);

  // Build Packages in referse order

  Map summaries = {};
  await _buildPackage(rootPath, packageGraph.root, summaries, dest);

  // Build index.html

  File index = new File(path.join(dest.path,"index.html"));

  return index.writeAsString(
"""
<html>
<head>
<script>
'use strict';
</script>
<script src='/home/vittorio/Tools/dev_compiler/lib/runtime/dart_library.js'></script>
<script src='/home/vittorio/Tools/dev_compiler/lib/runtime/dart_sdk.js'></script>
${summaries.keys.map((PackageNode n) => '<script src=\''+n.name+'.js\'></script>').join('\n')}
<script>
	// Start the main in module 'a'
	dart_library.start('${packageGraph.root.name}','${mainModule}');
</script>
</head>
<body>
</body>
</html>
""");
}

Future<List<String>> _buildPackage(String rootPath, PackageNode node,
    Map<PackageNode, List<String>> summaries, Directory dest) async {
  List<String> result;

  result = summaries[node];
  if (result != null) {
    return result;
  }

  // Build this package

  result = [];
  for (PackageNode dep in node.dependencies) {
    result.addAll(await _buildPackage(rootPath, dep, summaries, dest));
  }

  print("Building ${node.name}");
  result.add(await _buildOne(
      rootPath, node.name, new Directory.fromUri(node.location), dest, result));
  summaries[node] = result;

  return result;
}

Future<String> _buildOne(String rootPath, String packageName,
    Directory location, Directory dest, List<String> summaries) async {
  // Ottiene l'elenco di tutti i dart file di quel package
  List<String> sources = [];

  await _collectSources(
      packageName, new Directory(path.join(location.path, "lib")), sources);
  print("  Collected : ${sources}");
  print("  Summaries : ${summaries}");

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
  File js = new File(path.join(dest.path, "${packageName}.js"));
  await js.writeAsString(res.code);

  // Write source map
  File smap = new File(path.join(dest.path, "${packageName}.js.map"));
  await smap.writeAsString(JSON.encode(res.placeSourceMap(smap.path)));

  // Write summary

  File sum = new File(path.join(dest.path, "${packageName}.sum"));
  await sum.writeAsBytes(res.summaryBytes);

  print("BUILT : ${sum.path}");

  return sum.path;
}

class BuildError {
  List messages;

  BuildError(this.messages);

  toString() => messages.join("\n");
}

Future _collectSources(
    String packageName, Directory dir, List<String> sources) async {
  if (!await dir.exists()) {
    return [];
  }
  await for (FileSystemEntity e in dir.list(recursive: true)) {
    String rel = path.relative(e.path, from: dir.path);

    if (e is File) {
      if (path.extension(e.path) == '.dart') {
        sources.add("package:${packageName}/${rel}");
      }
    }
  }
}

String _moduleForLibrary(String moduleRoot, Source source) {
  if (source is InSummarySource) {
    var summaryPath = source.summaryPath;
    var ext = '.sum';
    if (path.isWithin(moduleRoot, summaryPath) && summaryPath.endsWith(ext)) {
      var buildUnitPath =
          summaryPath.substring(0, summaryPath.length - ext.length);
      return path.relative(buildUnitPath, from: moduleRoot);
    }

    throw 'Imported file ${source.uri} is not within the module root '
        'directory $moduleRoot';
  }

  throw 'Imported file "${source.uri}" was not found as a summary or source '
      'file. Please pass in either the summary or the source file '
      'for this import.';
}

main(List<String> args) {
  if (args == null || args.length != 3) {
    print("USAGE : dart devc_builder main_source_package_path output_path mainpackage_file_containing_main");
    return;
  }
  Chain.capture(() {
    _buildAll(args[0], new Directory(args[1]),args[2]);
  }, onError: (error, Chain chain) {
    if (error is BuildError) {
      print("BUILD ERROR : \n: ${error}");
    } else {
      print("ERROR: ${error}\n AT: ${chain.terse}");
    }
  });
}
