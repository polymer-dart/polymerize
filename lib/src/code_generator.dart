import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:analyzer/analyzer.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:code_builder/code_builder.dart' as code_builder;
import 'package:polymerize/src/dep_analyzer.dart';
import 'package:polymerize/src/utils.dart';

String toLibraryName(String uri) {
  Uri u = Uri.parse(uri);
  return u.pathSegments.map((x) => x.replaceAll('.', "_")).join("_") + "_G";
}

typedef Future CodeGenerator(GeneratorContext ctx, CompilationUnit cu, code_builder.LibraryBuilder libBuilder, code_builder.MethodBuilder initModuleBuilder, IOSink htmlHeader);

List<CodeGenerator> _codeGenerators = [_generateInitMethods,_generatePolymerRegister, _addHtmlImport];

class GeneratorContext {
  InternalContext ctx;
  String inputUri;

  GeneratorContext(this.ctx, this.inputUri);
}

Future generateCode(String inputUri, String genPath, String htmlTemp) async {
  InternalContext ctx = await InternalContext.create('.');

  CompilationUnit cu = ctx.getCompilationUnit(inputUri);

  GeneratorContext getctx = new GeneratorContext(ctx, inputUri);

  code_builder.LibraryBuilder libBuilder = new code_builder.LibraryBuilder(toLibraryName(inputUri));
  libBuilder.addDirective(new code_builder.ImportBuilder(inputUri, prefix: "_lib"));
  code_builder.MethodBuilder initModuleBuilder = new code_builder.MethodBuilder("initModule");
  libBuilder.addMember(initModuleBuilder);

  IOSink htmlTempSink = new File(htmlTemp).openWrite();

  await Future.wait(_codeGenerators.map((gen) => gen(getctx, cu, libBuilder, initModuleBuilder, htmlTempSink)));

  await htmlTempSink.close();

  initModuleBuilder
    ..addStatements([
      new code_builder.StatementBuilder.raw((scope) {
        return "return;";
      })
    ]);

  return new File(genPath).writeAsString(code_builder.prettyToSource(libBuilder.buildAst()));
}

/**
 * Look for INIT METHODS
 */

Future _generateInitMethods(
    GeneratorContext ctx, CompilationUnit cu, code_builder.LibraryBuilder libBuilder, code_builder.MethodBuilder initModuleBuilder, IOSink htmlHeader) async {
  for (CompilationUnitMember m in cu.declarations) {
    if (m.element?.kind == ElementKind.FUNCTION) {
      FunctionElement functionElement = m.element;
      DartObject init = getAnnotation(m.element.metadata, isInit);
      if (init != null && functionElement.parameters.isEmpty) {
        code_builder.ReferenceBuilder ref = code_builder.reference("_lib.${functionElement.name}");
        initModuleBuilder.addStatement(ref.call([]));
      }
    }
  }
}

Future _generatePolymerRegister(
    GeneratorContext ctx, CompilationUnit cu, code_builder.LibraryBuilder libBuilder, code_builder.MethodBuilder initModuleBuilder, IOSink htmlHeader) async {
  libBuilder.addDirective(new code_builder.ImportBuilder('package:polymer_element/polymerize.dart',prefix:'polymerize'));

  code_builder.TypeBuilder configType = new code_builder.TypeBuilder("polymerize.Config");
  code_builder.TypeBuilder summaryType = new code_builder.TypeBuilder('polymerize.Summary');

  code_builder.ReferenceBuilder ref = code_builder.reference("polymerize.register");

  code_builder.ReferenceBuilder configFactory = code_builder.reference("polymerize.config");
  code_builder.ReferenceBuilder summaryFactory = code_builder.reference("polymerize.summary");

  // lookup for annotation
  for (CompilationUnitMember m in cu.declarations) {
    if (m.element?.kind == ElementKind.CLASS) {
      ClassElement functionElement = m.element;
      DartObject register = getAnnotation(m.element.metadata, isPolymerRegister);
      if (register != null) {
        String tagName = register.getField('tagName').toStringValue();
        String template = register.getField('template').toStringValue();
        bool native = register.getField('native').toBoolValue();

        if (!native) {

          code_builder.ReferenceBuilder cls = code_builder.reference("_lib.${functionElement.name}");

          initModuleBuilder.addStatement(ref.call([cls,rawString(tagName),configFactory.call([]),summaryFactory.call([]),rawBool(false),rawString(template)]));
          if (template != null) {
            htmlHeader.writeln("<link rel='import' href='${template}'>");
          }
        }
      }
    }
  }



}

code_builder.ExpressionBuilder rawString(String value) => value!=null ? new code_builder.ExpressionBuilder.raw((_) => "'${value}'") : new code_builder.ExpressionBuilder.raw((_) => 'null');
code_builder.ExpressionBuilder rawBool(bool value) => new code_builder.ExpressionBuilder.raw((_) => value?'true':'false');

Future _addHtmlImport(GeneratorContext ctx, CompilationUnit cu, code_builder.LibraryBuilder libBuilder, code_builder.MethodBuilder initModuleBuilder, IOSink htmlHeader) async =>
    allFirstLevelAnnotation(cu, isHtmlImport).map((o) => o.getField('path').toStringValue()).forEach((relPath) => htmlHeader.writeln("<link rel='import' href='${relPath}'>"));
