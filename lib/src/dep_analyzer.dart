import 'dart:async';

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

log.Logger _logger = new log.Logger('deps');

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
  Map<String, Set<String>> depsByTarget = {};

  Set<String> importedPackages = new Set();
  String get rootPath => _ctx._rootPath;

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
    _logger.fine("PARSING ${file}");
    var absolutePath = pathos.absolute(file);
    var source = _ctx._analysisContext.sourceFactory.forUri(pathos.toUri(absolutePath).toString());

    CompilationUnit cu = _ctx._analysisContext.parseCompilationUnit(source);
    FindImports fu = new FindImports()..visitAllNodes(cu);

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
            importedPackages.add(pathos.canonicalize(otherPackageRoot));

            targetDesc = TargetDesc.fromPaths(packageRelativePath: m[3], rootPath: rootPath, packageRoot: otherPackageRoot, packageName: m[2]);
          }
        } else {
          // a relative path (relative to current file);
          String resolved = pathos.withoutExtension(pathos.join(pathos.dirname(file), u));

          String rel = pathos.relative(resolved, from: pathos.join(packageRoot, "lib"));

          targetDesc = TargetDesc.fromPaths(packageRelativePath: rel, rootPath: rootPath, packageRoot: packageRoot, packageName: _pubspec['name']);
        }
      }

      TargetDesc currentTarget = TargetDesc.fromPaths(
          packageName: _pubspec['name'],
          packageRoot: packageRoot,
          packageRelativePath: pathos.withoutExtension(pathos.relative(file, from: pathos.join(packageRoot, 'lib'))),
          rootPath: rootPath);

      depsByTarget.putIfAbsent(currentTarget.js, () => new Set<String>()).add(targetDesc.js);
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
  Map<String, DependencyAnalyzer> _analyzers = {};
  WorkspaceBuilder._(this._rootPath, this._mainPackagePath);

  static Future<WorkspaceBuilder> create(String rootPath, String mainPackagePath) async {
    WorkspaceBuilder b = new WorkspaceBuilder._(pathos.canonicalize(rootPath), pathos.canonicalize(mainPackagePath));

    await b.build(mainPackagePath);

    return b;
  }

  Future<DependencyAnalyzer> build(String packagePath) async {
    _ctx = await InternalContext.create(_rootPath);

    packagePath = pathos.canonicalize(packagePath);
    _logger.fine("BUILDING ${packagePath}");
    DependencyAnalyzer res = _analyzers[packagePath];
    if (res == null) {
      res = await analyzePackage(_rootPath, packagePath, _ctx);
      _analyzers[packagePath] = res;

      // Recur on imported packages
      await Future.wait(res.importedPackages.map((p) => build(p)));
    }
    return res;
  }

  get mainAnalyzer => this[_mainPackagePath];

  DependencyAnalyzer operator [](String packagePath) => _analyzers[pathos.canonicalize(packagePath)];
}

class TargetDesc {
  final String workspace_name;
  final String target;

  const TargetDesc([this.workspace_name, this.target]);

  static const SDK_TARGET = const TargetDesc("@polymerize//:", 'dart_sdk');

  String get js => "${workspace_name}${target}.js";

  static TargetDesc fromPaths({String packageRoot, String packageRelativePath, String rootPath, String packageName}) {
    String workspace_name;
    String target;
    if (pathos.isWithin(rootPath, packageRoot)) {
      workspace_name = ":";
      target = pathos.join(pathos.relative(packageRoot, from: rootPath), packageRelativePath);
    } else {
      workspace_name = "@${packageName}//:";
      target = packageRelativePath;
    }

    return new TargetDesc(workspace_name, target);
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
