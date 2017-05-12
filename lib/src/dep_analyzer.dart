import 'dart:async';

import 'dart:convert';
import 'package:analyzer/analyzer.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/src/dart/sdk/sdk.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/sdk.dart';
import 'package:analyzer/src/generated/source.dart';
import 'package:glob/glob.dart';
import 'package:package_resolver/package_resolver.dart';
import 'package:path/path.dart' as pathos;
import 'package:yaml/yaml.dart' as yaml;
import 'dart:io' as io;
import 'package:logging/logging.dart' as log;

log.Logger _logger = new log.Logger('deps')..level = log.Level.FINE;

class InternalContext {
  PackageResolver _packageResolver;
  AnalysisEngine engine = AnalysisEngine.instance;

  AnalysisContext _analysisContext;

  ResourceProvider _resourceProvider = PhysicalResourceProvider.INSTANCE;
  DartSdk _sdk;
  String _rootPath;

  InternalContext._(this._rootPath);

  static Future<InternalContext> create(String rootPath) async {
    InternalContext ctx = new InternalContext._(rootPath);
    await ctx._init();
    return ctx;
  }

  Future _init() async {
    _sdk = new FolderBasedDartSdk(_resourceProvider, FolderBasedDartSdk.defaultSdkDirectory(_resourceProvider));

    _analysisContext = engine.createAnalysisContext()
      ..analysisOptions = (new AnalysisOptionsImpl()
        ..strongMode = true
        ..analyzeFunctionBodies = true)
      ..sourceFactory = new SourceFactory([new ResourceUriResolver(_resourceProvider), new DartUriResolver(_sdk)]);

    _packageResolver = await PackageResolver.loadConfig(pathos.join(_rootPath, ".packages"));
  }
}

class DependencyAnalyzer {
  String packageRoot;
  Map _pubspec;
  InternalContext _ctx;
  Map<TargetDesc, Set<TargetDesc>> depsByTarget = {};

  Set<String> importedPackages = new Set();

  String get rootPath => _ctx._rootPath;

  String get packageName => _pubspec['name'];

  DependencyAnalyzer._(this.packageRoot, this._ctx);

  Future init() async {
    _pubspec = yaml.loadYaml(_ctx._resourceProvider.getFile(pathos.join(packageRoot, "pubspec.yaml")).readAsStringSync());
  }

  static Future<DependencyAnalyzer> create(String rootPath, String packageRoot, InternalContext _ctx) async {
    DependencyAnalyzer a = new DependencyAnalyzer._(packageRoot, _ctx);
    await a.init();
    return a;
  }

  static final RegExp re = new RegExp(r"^([^:]+):([^/]+)/(.+)\.dart$");

  Future analyze(String file) async {
    _logger.finest("PARSING ${file}");
    var absolutePath = pathos.absolute(file);
    var source = _ctx._analysisContext.sourceFactory.forUri(pathos.toUri(absolutePath).toString());

    CompilationUnit cu = _ctx._analysisContext.parseCompilationUnit(source);
    FindImports fu = new FindImports()..visitAllNodes(cu);
    TargetDesc currentTarget = TargetDesc.fromPaths(
        packageName: this.packageName,
        packageRoot: packageRoot,
        packageRelativePath: pathos.withoutExtension(pathos.relative(file, from: pathos.join(packageRoot, 'lib'))),
        rootPath: rootPath);
    depsByTarget[currentTarget] = new Set();

    Iterable<Future> futures = fu.uris.map((u) async {
      String workspace_name;
      String target;
      TargetDesc targetDesc;

      if (u.startsWith('dart:')) {
        targetDesc = TargetDesc.SDK_TARGET;
      } else {
        Match m = re.matchAsPrefix(u);

        if (m != null) {
          // an absolute url
          if (m[1] != 'package') {
            throw "Unknown uri prefix : ${m[1]}";
          } else {
            String otherPackageRoot = await _ctx._packageResolver.packagePath(m[2]);
            if (m[2]!=packageName)
              importedPackages.add(pathos.canonicalize(otherPackageRoot));

            targetDesc = TargetDesc.fromPaths(packageRelativePath: m[3], rootPath: rootPath, packageRoot: otherPackageRoot, packageName: m[2]);
          }
        } else {
          // a relative path (relative to current file);
          String resolved = pathos.withoutExtension(pathos.join(pathos.dirname(file), u));

          String rel = pathos.relative(resolved, from: pathos.join(packageRoot, "lib"));

          targetDesc = TargetDesc.fromPaths(packageRelativePath: rel, rootPath: rootPath, packageRoot: packageRoot, packageName: this.packageName);
        }
      }

      depsByTarget[currentTarget].add(targetDesc);
    });
    return Future.wait(futures);
  }
}

Future<DependencyAnalyzer> analyzePackage(String rootPath, String packageRoot, InternalContext ctx) async {
  Glob glob = new Glob("**.dart", recursive: true);

  DependencyAnalyzer dep = await DependencyAnalyzer.create(rootPath, packageRoot, ctx);

  String libPath = pathos.absolute(pathos.join(packageRoot, 'lib'));

  await for (io.FileSystemEntity f in glob.list(root: libPath)) {
    await dep.analyze(f.path);
  }

  return dep;
}

class WorkspaceBuilder {
  String _rootPath;
  String _mainPackagePath;
  InternalContext _ctx;
  Map<String, Future<DependencyAnalyzer>> _analyzersFutures = {};
  WorkspaceBuilder._(this._rootPath, this._mainPackagePath);

  static Future<WorkspaceBuilder> create(String rootPath, String mainPackagePath) async {
    WorkspaceBuilder b = new WorkspaceBuilder._(pathos.canonicalize(rootPath), pathos.canonicalize(mainPackagePath));

    _logger.finest("Start build workspace for ${rootPath}");

    await b.build(mainPackagePath);

    _logger.finest("Workspace builder created width ${b._allPackages.length} packages.");

    return b;
  }

  Future<DependencyAnalyzer> build(String packagePath) async {
    _ctx = await InternalContext.create(_rootPath);

    packagePath = pathos.canonicalize(packagePath);
    Future<DependencyAnalyzer> resFuture = _analyzersFutures.putIfAbsent(packagePath, () async {
      _logger.fine("ANALYZING ${packagePath}");
      DependencyAnalyzer res = await analyzePackage(_rootPath, packagePath, _ctx);
      _allPackages.add(packagePath);
      // Recur on imported packages
      _logger.finest("${packagePath} -> ${res.importedPackages}");
      await Future.wait(res.importedPackages.map((p) => build(p)));
      _logger.finest("Done ANALYZING ${packagePath}");
      return res;
    });

    return resFuture;
  }

  Set<String> _allPackages = new Set();
  /**
   * Generate the build for a package
   */
  Stream<String> generateBuildFile(String packagePath) async* {
    DependencyAnalyzer dep = await _analyzersFutures[packagePath];

    for (TargetDesc tgt in dep.depsByTarget.keys) {
      yield* _generateBuildFileForTarget(dep, tgt);
      yield "";
    }
  }

  Stream<String> _generateBuildFileForTarget(DependencyAnalyzer dep, TargetDesc target) async* {
    yield "dart_file(";
    yield " name = '${target.target}.js',";
    yield " deps = [";
    for (String dep in (dep.depsByTarget[target].toList()..sort((x, y) => x.js.compareTo(y.js))).map((x) => "'${x.relativeTo(target)}.js'")) {
      yield "   ${dep},";
    }
    yield " ])";
  }

  Future generateBuildFiles() async {
    String destBasePath = pathos.join(_rootPath, '.polymerize');

    io.Directory destBaseDir = new io.Directory(destBasePath);
    if (destBaseDir.existsSync()) {
      destBaseDir.deleteSync(recursive: true);
    }
    destBaseDir.createSync();

    for (String package in _allPackages) {
      DependencyAnalyzer dep = await _analyzersFutures[package];

      String buildFilePath = pathos.join(destBasePath, "BUILD.${dep.packageName}");

      try {
        _logger.fine("building ${buildFilePath}");
        await write(buildFilePath, generateBuildFile(package));
      } catch (error, stack) {
        _logger.severe("problem while writing ${dep.packageName} build file", error, stack);
      }
    }
  }
}

Future write(String dest, Stream<String> lines) async {
  io.File f = new io.File(dest);
  io.IOSink sink = f.openWrite();
  await writeSink(lines, sink);
  await sink.close();
}

Future writeSink(Stream<String> lines, io.IOSink sink) async {
  return sink.addStream(lines.map((x) => "${x}\n").transform(UTF8.encoder));
}

class TargetDesc {
  final String workspace_name;
  final String packageName;
  final String target;

  const TargetDesc({this.workspace_name: "//", this.packageName: "", this.target});

  static const SDK_TARGET = const TargetDesc(workspace_name: '@polymerize//', target: 'dart_sdk');

  String get baseLabel => '${workspace_name}${packageName}:${target}';

  String get js => "${baseLabel}.js";

  get hashCode => baseLabel.hashCode;
  bool operator ==(var other) => other is TargetDesc && this.baseLabel == other.baseLabel;

  static TargetDesc fromPaths({String packageRoot, String packageRelativePath, String rootPath, String packageName}) {
    String workspace_name;
    String packagePath;
    String target;
    if (pathos.isWithin(rootPath, packageRoot)) {
      workspace_name = "//";
      packagePath = pathos.relative(packageRoot, from: rootPath);
      target = packageRelativePath;
    } else {
      workspace_name = "@${packageName}//";
      packagePath = "";
      target = packageRelativePath;
    }

    return new TargetDesc(workspace_name: workspace_name, packageName: packagePath, target: target);
  }

  String relativeTo(TargetDesc root) {
    if (root.workspace_name != this.workspace_name) {
      return baseLabel;
    } else if (this.packageName != root.packageName) {
      return baseLabel;
    } else {
      return target;
    }
  }
}

class FindImports extends BreadthFirstVisitor<String> {
  List<String> uris = [];

  @override
  String visitImportDirective(ImportDirective node) {
    super.visitImportDirective(node);
    uris.add(node.uri.stringValue);
    return node.uri.stringValue;
  }
}
