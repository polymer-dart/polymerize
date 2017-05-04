import 'dart:async';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:build_runner/build_runner.dart' as build_runner;
import 'package:code_builder/code_builder.dart' as code_builder;
import 'package:polymerize/src/utils.dart';

class DartStubBuilder extends Builder {
  @override
  Future build(BuildStep buildStep) async {
    Resolver resolver = await buildStep.resolver;
    LibraryElement inputLib = resolver.getLibrary(buildStep.inputId);
    //StringBuffer buf = new StringBuffer();
    code_builder.LibraryBuilder libBuilder = new code_builder.LibraryBuilder();
    code_builder.MethodBuilder registerBuilder = new code_builder.MethodBuilder("register");
    libBuilder.addMember(registerBuilder);

    inputLib.unit.declarations.forEach((ce) {
      if (ce.element.kind == ElementKind.CLASS) {
        ce.element.metadata.forEach((e) => print(e.element.name));
        DartObject registerAnnotation = getAnnotation(ce.element.metadata, isPolymerRegister);
        if (registerAnnotation == null) {
          registerBuilder.addStatement(new code_builder.StatementBuilder.raw((scope) => "print('skipped');"));
          print("ANNOTATIONS : ${ce.element.metadata.map((e) => e.computeConstantValue().type.element.source.uri).join("/")}");
          return;
        }
        String tagName = registerAnnotation.getField('tagName').toStringValue();

        registerBuilder
          ..addStatements([
            new code_builder.StatementBuilder.raw((scope) {
              return "polymerize(${ce.element.name},'${tagName}');";
            })
          ]);
      }
    });
    AssetId dest = buildStep.inputId.changeExtension(".reg.dart");
    await buildStep.writeAsString(dest, code_builder.prettyToSource(libBuilder.buildAst()));
  }

  @override
  Map<String, List<String>> get buildExtensions => {
        ".dart": [".reg.dart"]
      };
}

Future build(String package, List<String> inputFiles) {
  build_runner.PhaseGroup phaseGroup = new build_runner.PhaseGroup();
  phaseGroup.newPhase()..addAction(new DartStubBuilder(), new build_runner.InputSet(package, inputFiles));

  return build_runner.build(phaseGroup);
}
