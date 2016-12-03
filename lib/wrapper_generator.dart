import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'package:package_resolver/package_resolver.dart';
import 'package:path/path.dart' as path;

runGenerateWrapper(ArgResults params) async {
  PackageResolver resolver = PackageResolver.current;
  //new res.Resource('package:polymerize/src/js/analyze.js');

  String relPath =   path.relative(params['file-path'],from:params['base-dir']);

  ProcessResult res = await Process.run('node', [
    (await resolver.resolveUri('package:polymerize/src/js/analyze.js')).toFilePath(),
    params['base-dir'],
    relPath
  ],stdoutEncoding: UTF8);

  var result = JSON.decode(res.stdout);

  generate_elements("src/${relPath}",result);
  generate_behaviors("src/${relPath}",result);
  //print("RES = ${result}");

}

generate_elements(relPath,result) {
  Map<String,Map> elements = result['elements'];
  if (elements==null)
    return;
  elements.forEach((name,descr){
    String res = generate_element(relPath,name,descr);
    print(res);
  });
}

generate_behaviors(relPath,result) {
  Map<String,Map> elements = result['behaviors'];
  if (elements==null)
    return;
  elements.forEach((name,descr){
    String res = generate_behavior(relPath,name,descr);
    print(res);
  });
}

generate_element(String relPath,String name,Map descr) {
  return """
@JS('PolymerElements')
library ${name};
import 'dart:html';
import 'package:js/js.dart';
import 'package:polymer_element/polymer_element.dart';
${importBehaviors(relPath,name,descr)}

${generateComment(descr['description'])}

abstract class PaperButtonBehavior {
  bool get raised;
  set raised(bool value);
}

//@JS('PaperButton')
@PolymerRegister('${descr['name']}',template:'${relPath}',native:true)
class ${name} extends PolymerElement ${withBehaviors(relPath,name,descr)} {
${generateProperties(relPath,name,descr,descr['properties'])}
}
""";
}

generate_behavior(String relPath,String name,Map descr) {
  return """
@JS('PolymerElements')
library ${name};
import 'dart:html';
import 'package:js/js.dart';
import 'package:polymer_element/polymer_element.dart';
${importBehaviors(relPath,name,descr)}

${generateComment(descr['description'])}

@PolymerRegister('${descr['name']}',template:'${relPath}',native:true,behavior:true)
abstract class ${name}  ${withBehaviors(relPath,name,descr)} {
${generateProperties(relPath,name,descr,descr['properties'])}
}

""";
}

withBehaviors(String relPath,String name,Map descr) {
  List behaviors = descr['behaviors'];
  if (behaviors == null) {
    return "";
  }

  return  "with " + behaviors.map((behavior) => withBehavior(relPath,name,descr,behavior)).join(',');
}

withBehavior(String relPath,String name,Map descr,Map behavior) => behavior['name'];

indents(int i,String s) => ((p,s) => s.split("\n").map((x) => p+x).join("\n"))(UTF8.decode(new List.filled(i, UTF8.encode(" ").first)),s);

generateComment(String comment,{int indent:0}) => indents(indent,"/**\n * "+comment.split(new RegExp("\n+")).join("\n * ")+"\n */");

importBehaviors(String relPath,String name,Map descr) => descr['behaviors'].map((b)=>'import \'package:polymer_elements/${b['name']}/${b['name']}\';').join('\n');

generateProperties(String relPath,String name,Map descr,Map properties) {
  if (properties == null) {
    return "";
  }

  return properties.values.map((p) => generateProperty(relPath,name,descr,p)).join("\n");
}

generateProperty(String relPath,String name,Map descr,Map prop) => """
${generateComment(prop['description'],indent:2)}
  ${prop['type']} get ${prop['name']}();
  void set ${prop['name']}(${prop['type']} value);
""";
