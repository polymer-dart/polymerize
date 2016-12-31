import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'package:path/path.dart' as path;
import 'package:polymerize/package_graph.dart';

const String RULES_VERSION = 'v_0_0_7';

Iterable<PackageNode> _transitiveDeps(PackageNode n, {Set<PackageNode> visited}) sync* {
  if (visited == null) {
    visited = new Set();
  }

  for (PackageNode d in (n.dependencies ?? [])) {
    yield* _transitiveDeps(d, visited: visited);
    if (!visited.contains(d)) {
      visited.add(d);
      yield d;
    }
  }
}

_depsFor(PackageNode g, PackageNode root) => _transitiveDeps(g).map((PackageNode n) => _asDep(n, root)).join(",");

_asDep(PackageNode n, PackageNode root) {
  if (n.dependencyType == PackageDependencyType.root) {
    return '":${n.name}"';
  }
  if (n.dependencyType != PackageDependencyType.path || _isExternal(n, root)) {
    return '"@${n.name}//:${n.name}"';
  } else {
    return '"//${path.relative(n.location.toFilePath(),from:root.location.toFilePath())}"';
  }
}

bool _isExternal(PackageNode n, PackageNode root) => !path.isWithin(root.location.toFilePath(), n.location.toFilePath());

String _libDeps(PackageGraph g) => g.allPackages.values
    .map((PackageNode n) => <PackageDependencyType, Function>{
          PackageDependencyType.pub: (PackageNode n) => """
dart_library(
  name='${n.name}',
  deps= [${_depsFor(n,g.root)}],
  package_name='${n.name}',
  pub_host = '${n.source['description']['url']}/api',
  version='${n.version}')
""",
          PackageDependencyType.github: (PackageNoden) => """git_repository(
    name = "${n.name}",
    remote = "${n.source['description']['url']}",
    tag = "${n.source['description']['ref']}",
)
""",
          PackageDependencyType.path: (PackageNode n) => _isExternal(n, g.root)
              ? """
dart_library(
  name='${n.name}',
  deps= [${_depsFor(n,g.root)}],
  src_path='${n.location.toFilePath()}',
  #pub_host = 'http://pub.drafintech.it:5001/api',
  package_name='${n.name}',
  version='${n.version}')
"""
              : null,
          PackageDependencyType.root: (PackageNode n) => null,
        }[n.dependencyType](n))
    .where((x) => x != null)
    .join("\n\n");

_generateWorkspaceFile(PackageGraph g, String destDir, {String developHome}) async {
  File workspace = new File(path.join(destDir, "WORKSPACE"));
  //print(g.allPackages.values.map((PackageNode p) => p.toString()).join("\n"));

  if (developHome == null) {
    await workspace.writeAsString("""
# Polymerize rules repository
git_repository(
 name='polymerize',
 tag='${RULES_VERSION}',
 remote='https://github.com/dam0vm3nt/bazel_polymerize_rules')

# Load Polymerize rules
load('@polymerize//:polymerize_workspace.bzl',
    'dart_library',
    'init_polymerize')

# Init
init_polymerize()


##
## All the dart libraries we depend on
##

${_libDeps(g)}

""");
  } else {
    await workspace.writeAsString("""
# Polymerize rules repository

local_repository(
 name='polymerize',
 path='${path.join(developHome,'bazel_polymerize_rules')}'
)

# Load Polymerize rules
load('@polymerize//:polymerize_workspace.bzl',
    'dart_library',
    'init_local_polymerize')

# Init
init_local_polymerize('${path.join(developHome,'polymerize')}')


##
## All the dart libraries we depend on
##

${_libDeps(g)}

""");
  }
}

_generateBuildFiles(PackageNode g, PackageNode r, String destDir, {Iterable<PackageNode> allPackages}) async {
  // Deps first
  await Future.wait(g.dependencies.where((PackageNode d) => d.dependencyType == PackageDependencyType.path && !_isExternal(d, r)).map((PackageNode d) async {
    await _generateBuildFiles(d, r, destDir);
  }));

  // Then us
  String dd = path.join(g.location.toFilePath(), "BUILD");
  //print("Loc : ${dd}");
  if (g.dependencyType == PackageDependencyType.root)
    await new File(dd).writeAsString("""
load("@polymerize//:polymerize.bzl", "polymer_library", "bower")

package(default_visibility = ["//visibility:public"])

polymer_library(
    name = "${g.name}",
    package_name = "${g.name}",
    base_path = "//:lib",
    dart_sources = glob(["lib/**/*.dart"]),
    export_sdk = 1,
    html_templates = glob(
        [
            "lib/**",
            "web/**",
        ],
        exclude = ["**/*.dart"],
    ),
    version = "${g.version}",
    deps = [
        ${_depsFor(g,r)}
    ],
)


# TODO : IMPLEMENT THIS AS AN ASPECT
bower(
    name = "main",
    resolutions = {
        "polymer": "2.0-preview",
    },
    deps = [
    ${allPackages.map((p) => _asDep(p,r)).join(",\n\         ")}
    ],
)

filegroup(
    name = "default",
    srcs = [
        "main",
        "${g.name}",
    ],
)
""");
  else {
    String relPath = path.relative(g.location.toFilePath(), from: r.location.toFilePath());
    await new File(dd).writeAsString("""
load("@polymerize//:polymerize.bzl", "polymer_library")

package(default_visibility = ["//visibility:public"])

polymer_library(
    name = "${g.name}",
    package_name = "${g.name}",
    base_path = "//${relPath}:lib",
    dart_sources = glob(["lib/**/*.dart"]),
    html_templates = glob(
        ["lib/**"],
        exclude = ["lib/**/*.dart"],
    ),
    version = "1.0",
    deps = [
        ${_depsFor(g,r)}
    ],
)
""");
  }
}

runInit(ArgResults args) async {
  var mainDir = path.dirname(args['pubspec']);
  String develop = args['develop'];
  PackageGraph g = new PackageGraph.forPath(mainDir);
  await _generateWorkspaceFile(g, mainDir, developHome: develop != null ? path.canonicalize(develop) : null);
  await _generateBuildFiles(g.root, g.root, mainDir, allPackages: g.allPackages.values);
}
