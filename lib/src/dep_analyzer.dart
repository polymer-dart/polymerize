import 'dart:async';

import 'dart:convert';
import 'package:analyzer/analyzer.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/src/dart/sdk/sdk.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/source.dart';
import 'package:analyzer/source/pub_package_map_provider.dart';
import 'package:analyzer/source/package_map_resolver.dart';
import 'package:glob/glob.dart';
import 'package:package_resolver/package_resolver.dart';
import 'package:path/path.dart' as pathos;
import 'package:polymerize/package_graph.dart';
import 'package:yaml/yaml.dart' as yaml;
import 'dart:io' as io;
import 'package:logging/logging.dart' as log;

log.Logger _logger = new log.Logger('deps')..level = log.Level.FINE;

class InternalContext {
  PackageResolver _packageResolver;
  AnalysisEngine engine = AnalysisEngine.instance;

  AnalysisContext _analysisContext;

  ResourceProvider _resourceProvider = PhysicalResourceProvider.INSTANCE;
  FolderBasedDartSdk _sdk;
  String _rootPath;

  PackageGraph _pkgGraph;

  InternalContext._(this._rootPath);

  static Future<InternalContext> create(String rootPath) async {
    InternalContext ctx = new InternalContext._(rootPath);
    await ctx._init();
    return ctx;
  }

  Future _init() async {
    _sdk = new FolderBasedDartSdk(_resourceProvider, FolderBasedDartSdk.defaultSdkDirectory(_resourceProvider));

    ResourceUriResolver _resourceResolver = new ResourceUriResolver(_resourceProvider);

    _packageResolver = await PackageResolver.loadConfig(pathos.join(_rootPath, ".packages"));

    PubPackageMapProvider _pub = new PubPackageMapProvider(_resourceProvider,_sdk);
    PackageMapUriResolver _pkgRes= new PackageMapUriResolver(_resourceProvider, _pub.computePackageMap(_resourceProvider.getFolder(_rootPath)).packageMap);

    _analysisContext = engine.createAnalysisContext()
      ..analysisOptions = (new AnalysisOptionsImpl()
        ..strongMode = true
        ..analyzeFunctionBodies = true)
      ..sourceFactory = new SourceFactory([new DartUriResolver(_sdk),_resourceResolver,_pkgRes]);

    _pkgGraph = new PackageGraph.forPath(_rootPath);
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

  bool get external => !(pathos.isWithin(rootPath, packageRoot) || rootPath == packageRoot);

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
    //var source = _ctx._analysisContext.sourceFactory.forUri(pathos.toUri(absolutePath).toString());

    CompilationUnit cu = parseDirectives(await new io.File(file).readAsString()); //  _ctx._analysisContext.parseCompilationUnit(source);
    FindImports fu = new FindImports()..visitAllNodes(cu);
    TargetDesc currentTarget = TargetDesc.fromPaths(
        packageName: this.packageName,
        packageRoot: packageRoot,
        packageRelativePath: pathos.withoutExtension(pathos.relative(file, from: pathos.join(packageRoot, 'lib'))),
        rootPath: rootPath);
    depsByTarget[currentTarget] = new Set();

    Iterable<Future> futures = fu.uris.where((u) => !u.startsWith('dart:')).map((u) async {
      String workspace_name;
      String target;
      TargetDesc targetDesc;

      Match m = re.matchAsPrefix(u);

      if (m != null) {
        // an absolute url
        if (m[1] != 'package') {
          throw "Unknown uri prefix : ${m[1]}";
        } else {
          String otherPackageRoot = await _ctx._packageResolver.packagePath(m[2]);
          if (m[2] != packageName) importedPackages.add(pathos.canonicalize(otherPackageRoot));

          targetDesc = TargetDesc.fromPaths(packageRelativePath: m[3], rootPath: rootPath, packageRoot: otherPackageRoot, packageName: m[2]);
        }
      } else {
        // a relative path (relative to current file);
        String resolved = pathos.withoutExtension(pathos.join(pathos.dirname(file), u));

        String rel = pathos.relative(resolved, from: pathos.join(packageRoot, "lib"));

        targetDesc = TargetDesc.fromPaths(packageRelativePath: rel, rootPath: rootPath, packageRoot: packageRoot, packageName: this.packageName);
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
  Map<String, DependencyAnalyzer> _analyzers = {};
  WorkspaceBuilder._(this._rootPath, this._mainPackagePath);

  static Future<WorkspaceBuilder> create(String rootPath, String mainPackagePath) async {
    WorkspaceBuilder b = new WorkspaceBuilder._(pathos.canonicalize(rootPath), pathos.canonicalize(mainPackagePath));

    _logger.finest("Start build workspace for ${rootPath}");

    await b.build(mainPackagePath);

    _logger.finest("Workspace builder created width ${b._analyzers.length} packages.");

    return b;
  }

  Map<TargetDesc, DependencyAnalyzer> depByTarget = <TargetDesc, DependencyAnalyzer>{};

  Future<DependencyAnalyzer> build(String packagePath, [Map<String, Future<DependencyAnalyzer>> _analyzersFutures]) async {
    if (_analyzersFutures == null) {
      _analyzersFutures = new Map();
    }
    _ctx = await InternalContext.create(_rootPath);

    packagePath = pathos.canonicalize(packagePath);
    Future<DependencyAnalyzer> resFuture = _analyzersFutures.putIfAbsent(packagePath, () async {
      _logger.fine("ANALYZING ${packagePath}");
      DependencyAnalyzer res = await analyzePackage(_rootPath, packagePath, _ctx);
      //_allPackages.add(packagePath);
      res.depsByTarget.keys.forEach((t) => depByTarget[t] = res);

      // Recur on imported packages
      _logger.finest("${packagePath} -> ${res.importedPackages}");
      await Future.wait(res.importedPackages.map((p) => build(p, _analyzersFutures)));
      _logger.finest("Done ANALYZING ${packagePath}");

      _analyzers[packagePath] = res;

      return res;
    });

    return resFuture;
  }

  //Set<String> _allPackages = new Set();

  Iterable<String> get _allPackages => _analyzers.keys;

  /**
   * Generate the build for a package
   */
  Stream<String> generateBuildFile(String packagePath) async* {
    yield 'load("@polymerize//:polymerize.bzl", "dart_file","export_dart_sdk")';
    yield "";
    yield "def build():";
    DependencyAnalyzer dep = _analyzers[packagePath];

    if (packagePath == _mainPackagePath) {
      yield "  export_dart_sdk(name ='dart_sdk')";
    }

    for (TargetDesc tgt in dep.depsByTarget.keys) {
      yield* _generateBuildFileForTarget(dep, tgt);
      yield "";
    }
  }

  Stream<String> _generateBuildFileForTarget(DependencyAnalyzer dep, TargetDesc target) async* {
    yield "  dart_file(";
    yield "   name = '${target.target}',";
    yield "   dart_sources = ['lib/${target.target}.dart'],";
    yield "   dart_source_uri = '${target.uri}',";
    yield "   deps = [";
    for (String dep in (new List.from(new Set()..addAll(_transitiveDependencies(target)))..sort((x, y) => x.js.compareTo(y.js))).map((x) => "'${x.relativeTo(target)}'")) {
      yield "     ${dep},";
    }
    yield "  ])";


    // Analyze target and get any interesting thing

    LibraryElement lib = resolve(target);

    // TODO :
    // Generare gli stub dart files da qualche parte oppure il task per farlo generare (e poi compilare e produrre il .mod.html come al solito)
    // Generare i repository per i bower
    // Generare le istruzioni per caricare file extra in HTML

    //lib.importedLibraries.forEach((el)=>_logger.info("LIBRARIES FOR ${lib.location} : ${el.location}"));
  }

  Iterable<TargetDesc> _transitiveDependencies(TargetDesc startTarget, {Set<TargetDesc> visited}) sync* {
    // Lookup a dep for this target
    if (visited == null) {
      visited = new Set();
    }

    if (visited.contains(startTarget)) {
      return;
    }
    visited.add(startTarget);

    DependencyAnalyzer dep = depByTarget[startTarget];
    for (TargetDesc child in dep.depsByTarget[startTarget]) {
      yield child;
      yield* _transitiveDependencies(child, visited: visited);
    }
  }

  LibraryElement resolve(TargetDesc target, {Map<TargetDesc, LibraryElement> inProcess}) {
    if (inProcess == null) {
      inProcess = new Map();
    }
    return inProcess.putIfAbsent(target, () {
      depByTarget[target].depsByTarget[target].forEach((t) => resolve(t, inProcess: inProcess));

      // And finally resolve me

      Uri uri = target.uri;
      _logger.finest("Resolving : ${uri}");
      Source src = _ctx._analysisContext.sourceFactory.forUri2(uri);
      return _ctx._analysisContext.computeLibraryElement(src);

    });
  }

  Future generateBuildFiles() async {
    String destBasePath = pathos.join(_rootPath, '.polymerize');

    io.Directory destBaseDir = new io.Directory(destBasePath);
    if (destBaseDir.existsSync()) {
      destBaseDir.deleteSync(recursive: true);
    }
    destBaseDir.createSync();

    for (String package in _allPackages) {
      DependencyAnalyzer dep = _analyzers[package];

      String buildFilePath = pathos.join(destBasePath, "BUILD.${dep.packageName}.bzl");

      try {
        _logger.fine("building ${buildFilePath}");
        await write(buildFilePath, generateBuildFile(package));
      } catch (error, stack) {
        _logger.severe("problem while writing ${dep.packageName} build file", error, stack);
      }
    }

    // Create BUILD PATH FOR .polymerize WORKSPACE
    await write(pathos.join(destBasePath, "BUILD"), new Stream.fromIterable(['package(default_visibility = ["//visibility:public"])']));

    // create INNER BUILD files
    for (String package in _allPackages) {
      DependencyAnalyzer dep = _analyzers[package];
      if (dep.external) continue;

      String buildFilePath = pathos.join(dep.packageRoot, "BUILD");

      try {
        _logger.fine("building ${buildFilePath}");
        await write(buildFilePath, _generateMainBuildFile(package, dep));
      } catch (error, stack) {
        _logger.severe("problem while writing ${dep.packageName} build file", error, stack);
      }
    }

    // Create WORKSPACE file

    await write(pathos.join(destBasePath, "WORKSPACE.main.bzl"), generateWorkspaceBzl());

    await write(pathos.join(_rootPath, 'WORKSPACE'), _generateMainWorspace());
  }

  Stream<String> _generateMainBuildFile(String path, DependencyAnalyzer dep) async* {
    yield 'load("@build_files//:BUILD.${dep.packageName}.bzl","build")';
    yield 'package(default_visibility = ["//visibility:public"])';
    yield 'build()';

    if (path == _mainPackagePath) {
      yield "filegroup(name='all_js',srcs=['dart_sdk',${dep.depsByTarget.keys.map((t)=>"'${t.target}'").join(',')}])";
    }
  }

  Stream<String> _generateMainWorspace() {
    if (developHome != null)
      return _stream("""
local_repository(
 name='polymerize',
 path='${pathos.join(developHome,'bazel_polymerize_rules')}'
)

local_repository(
 name='build_files',
 path='.polymerize')

load('@build_files//:WORKSPACE.main.bzl','load_repositories')

load_repositories()
  
  """);
    else
      return _stream("""
# Polymerize rules repository
git_repository(
 name='polymerize',
 tag='${rules_version}',
 remote='https://github.com/polymer-dart/bazel_polymerize_rules')    
    """);
  }

  String developHome = '/home/vittorio/Develop/dart';
  String rules_version = '0.9';
  String get sdk_home => pathos.join(_ctx._sdk.directory.path, 'bin');

  static Stream<String> _stream(String bigString, {int indent: 0}) =>
      new Stream.fromIterable(bigString.split("\n").map((x) => new String.fromCharCodes(new List.generate(indent, (x) => ' '.codeUnits.first)) + x));

  Stream<String> generateWorkspaceBzl() async* {
    if (developHome == null) {
      yield* _stream("""
# Load Polymerize rules
load('@polymerize//:polymerize_workspace.bzl',
    'dart_library2',
    'init_polymerize')

def load_repositories() :
   # Init
   init_polymerize('${sdk_home}')


   ##
   ## All the dart libraries we depend on
   ##""");

      yield* _generateDeps();
    } else {
      yield* _stream("""
# Load Polymerize rules
load('@polymerize//:polymerize_workspace.bzl',
    'dart_library2',
    'init_local_polymerize')


def load_repositories() :
   # Init
   init_local_polymerize('${sdk_home}','${pathos.join(developHome,'polymerize')}')
    
   ##
   ## All the dart libraries we depend on
   ##""");

      yield* _generateDeps();
    }
  }

  Stream<String> _generateDeps() async* {
    for (String packageName in _allPackages) {
      // If is external write
      DependencyAnalyzer dep = _analyzers[packageName];

      yield* _generateDepsForPackage(packageName, dep);
    }
  }

  Stream<String> _generateDepsForPackage(String packagePath, DependencyAnalyzer dep) async* {
    // Nothing to do if it is internal
    if (pathos.isWithin(_rootPath, packagePath)) {
      return;
    }

    PackageNode nd = _ctx._pkgGraph.allPackages[dep.packageName];

    dartLibraryWriter writer = _dartLibraryWriters[nd.dependencyType];

    if (writer != null) yield* _stream(writer(nd), indent: 3);
  }
}

/**
 * Writers for external deps
 */

Map<PackageDependencyType, dartLibraryWriter> _dartLibraryWriters = <PackageDependencyType, dartLibraryWriter>{
  PackageDependencyType.pub: (PackageNode n) => """
dart_library2(
  name='${n.name}',
  package_name='${n.name}',
  pub_host = '${n.source['description']['url']}/api',
  version='${n.version}')
""",
  PackageDependencyType.github: (PackageNode n) => """git_repository(
    name = "${n.name}",
    remote = "${n.source['description']['url']}",
    tag = "${n.source['description']['ref']}",
)
""",
  PackageDependencyType.path: (PackageNode n) => """
dart_library2(
  name='${n.name}',
  src_path='${n.location.toFilePath()}',
  package_name='${n.name}',
  version='${n.version}')
""",
  PackageDependencyType.root: null,
};

typedef String dartLibraryWriter(PackageNode nd);

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
  final Uri uri;

  const TargetDesc({this.workspace_name: "//", this.packageName: "", this.target, this.uri});

  static const SDK_TARGET = const TargetDesc(workspace_name: '//', target: 'dart_sdk');

  String get baseLabel => '${workspace_name}${packageName}:${target}';

  String get js => "${baseLabel}.js";

  get hashCode => baseLabel.hashCode;
  bool operator ==(var other) => other is TargetDesc && this.baseLabel == other.baseLabel;

  static TargetDesc fromPaths({String packageRoot, String packageRelativePath, String rootPath, String packageName}) {
    String workspace_name;
    String packagePath;
    String target;
    if (pathos.isWithin(rootPath, packageRoot) || rootPath == packageRoot) {
      workspace_name = "//";
      packagePath = pathos.relative(packageRoot, from: rootPath);
      target = packageRelativePath;
    } else {
      workspace_name = "@${packageName}//";
      packagePath = "";
      target = packageRelativePath;
    }

    return new TargetDesc(
        workspace_name: workspace_name, packageName: packagePath, target: target,
        uri: Uri.parse('package:${packageName}/${packageRelativePath}.dart'));
  }

  String relativeTo(TargetDesc root) {
    if (root.workspace_name != this.workspace_name || this.packageName != root.packageName) {
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
