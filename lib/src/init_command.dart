import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'package:path/path.dart' as path;
import 'package:polymerize/package_graph.dart';

runInit(ArgResults args) async {
  PackageGraph g = new PackageGraph.forPath(args['pubspec']);

}