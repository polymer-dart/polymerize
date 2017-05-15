import 'dart:convert';
import 'dart:io';

String toLibraryName(String uri) {
  Uri u = Uri.parse(uri);
  return u.pathSegments.map((x) => x.replaceAll('.', "_")).join("_") + "_G";
}

generateCode(String inputUri,String genPath) async {
  // Per ora genera in modo molto semplice
  IOSink sinkDart = new File(genPath).openWrite();
  await sinkDart.addStream(() async* {
    yield "library ${toLibraryName(inputUri)};\n\n";
    yield "import '${inputUri}';\n";
    yield "\n";
    yield "initModule() {\n";
    // TODO : write register code for each polymer element
    yield "  // TODO: write code here\n";
    yield "}\n";
  }()
                               .transform(UTF8.encoder));
  await sinkDart.close();
}