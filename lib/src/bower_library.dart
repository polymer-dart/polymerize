import 'dart:async';

import 'package:logging/logging.dart';
import 'dart:io' as io;
import 'package:path/path.dart' as pathos;

Logger _logger = new Logger('bower_library');

Future createBowerLibrary(String repo) async {

  // first of all update the bower thing

  // Run bower command
  _logger.info("RUNNING BOWER in ${repo}");
  io.Directory dir = new io.Directory(repo);
  io.ProcessResult res = await io.Process.run('bower', ['update'],workingDirectory: dir.path);
  if (res.exitCode!=0) {
    throw "ERROR : ${res.stderr}\nOUT : ${res.stdout}";
  }

  // Now build the BUILD file
  io.IOSink sink = new io.File(pathos.join(dir.path,'BUILD')).openWrite();
  sink.writeln('package(default_visibility = ["//visibility:public"])');
  sink.writeln('load("@polymerize//:polymerize.bzl", "simple_asset")');


  io.Directory bower_components = new io.Directory(pathos.join(dir.path,'bower_components'));
  List<String> assets = [];
  await for (io.FileSystemEntity ent in bower_components.list(recursive: true)) {
    if (ent is io.Directory) {
      continue;
    }
    String path = pathos.relative(ent.path,from:bower_components.path);
    String asset = "assets/${path}";
    assets.add("'//:${asset}'");
    sink.writeln('simple_asset( name="${asset}", path=["//:bower_components/${path}"] )');
  }

  sink.writeln("filegroup( name='all_assets', srcs=[");
  assets.forEach((a) => sink.writeln("  ${a},"));
  sink.writeln("])");

  await sink.close();

}