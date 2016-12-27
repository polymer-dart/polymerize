
import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'package:path/path.dart' as path;



runBowerMode(ArgResults res) async {
  File dest = new File(res['output']);

  Map<String, String> allDeps = {};

  for (String dep in res['use-bower']) {
    List cont = await new File(dep).readAsLines();
    if (cont != null) allDeps.addAll(JSON.decode("{${cont.join(",")}}"));
  }

  await dest.writeAsString(JSON.encode({
                                         "name": "_polymerize_generated_bower_file_",
                                         "private": true,
                                         "dependencies": allDeps,
                                         "resolutions": new Map.fromIterables(res['resolution-key'], res['resolution-value'])
                                       }));
  // Execute bower
  Directory tmp = new Directory(path.absolute(path.dirname(dest.path)));
  print("Running bower with ${dest.path}");
  //tmp.createSync(recursive: true);
  //File c = new File(path.join(tmp.path,"bower.json"));
  //dest.copySync(c.path);
  print("Downloading JS components");
  ProcessResult x = await Process.run("bower", ["install", "-s"], workingDirectory: tmp.path, environment: {"HOME": tmp.path});
  print("Bower install finished : ${x.stdout} , ${x.stderr}");
}
