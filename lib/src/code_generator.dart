import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:analyzer/analyzer.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:code_builder/code_builder.dart' as code_builder;
import 'package:polymerize/src/dep_analyzer.dart';
import 'package:polymerize/src/utils.dart';

String toLibraryName(String uri) {
  Uri u = Uri.parse(uri);
  return u.pathSegments.map((x) => x.replaceAll('.', "_")).join("_") + "_G";
}

typedef Future CodeGenerator(GeneratorContext ctx, CompilationUnit cu, code_builder.LibraryBuilder libBuilder, code_builder.MethodBuilder initModuleBuilder, IOSink htmlHeader);

List<CodeGenerator> _codeGenerators = [_generateInitMethods, _generatePolymerRegister, _addHtmlImport];

class GeneratorContext {
  InternalContext ctx;
  String inputUri;

  GeneratorContext(this.ctx, this.inputUri);
}

Future generateCode(String inputUri, String genPath, String htmlTemp) async {
  InternalContext ctx = await InternalContext.create('.');

  CompilationUnit cu = ctx.getCompilationUnit(inputUri);

  GeneratorContext getctx = new GeneratorContext(ctx, inputUri);

  code_builder.Scope scope = new code_builder.Scope.dedupe();
  code_builder.LibraryBuilder libBuilder = new code_builder.LibraryBuilder.scope(name:toLibraryName(inputUri),scope:scope);
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

  return new File(genPath).writeAsString(code_builder.prettyToSource(libBuilder.buildAst(scope)));
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
        code_builder.ReferenceBuilder ref = code_builder.reference(functionElement.name,ctx.inputUri);
        initModuleBuilder.addStatement(ref.call([]));
      }
    }
  }
}

const String POLYMERIZE_JS = 'package:polymer_element/polymerize_js.dart';
const String JS_UTIL = 'package:js/js_util.dart';

Future _generatePolymerRegister(
    GeneratorContext ctx, CompilationUnit cu, code_builder.LibraryBuilder libBuilder, code_builder.MethodBuilder initModuleBuilder, IOSink htmlHeader) async {
  //libBuilder.addDirective(new code_builder.ImportBuilder('package:polymer_element/polymerize_js.dart', prefix: 'polymerize'));
  //libBuilder.addDirective(new code_builder.ImportBuilder('package:js/js_util.dart', prefix: 'js_util'));

  code_builder.TypeBuilder summaryType = new code_builder.TypeBuilder('Summary', importFrom: POLYMERIZE_JS);

  code_builder.ReferenceBuilder ref = code_builder.reference("register",POLYMERIZE_JS);

  code_builder.ReferenceBuilder defBehavior = code_builder.reference("defineBehavior",POLYMERIZE_JS);

  code_builder.ReferenceBuilder summaryFactory = code_builder.reference("summary",POLYMERIZE_JS);

  // lookup for annotation
  for (CompilationUnitMember m in cu.declarations) {
    if (m.element?.kind == ElementKind.CLASS) {
      ClassElement classElement = m.element;
      DartObject register = getAnnotation(m.element.metadata, isPolymerRegister);
      if (register != null) {
        String tagName = register.getField('tagName').toStringValue();
        String template = register.getField('template').toStringValue();
        bool native = register.getField('native').toBoolValue();

        if (!native) {
          code_builder.ReferenceBuilder cls = code_builder.reference(classElement.name,ctx.inputUri);

          code_builder.ExpressionBuilder configExpressionBuilder = collectConfig(libBuilder, ctx.ctx.analysisContext, classElement);

          initModuleBuilder.addStatement(
              ref.call([cls, code_builder.literal(tagName), configExpressionBuilder, summaryFactory.call([]), code_builder.literal(false), code_builder.literal(template)]));
          if (template != null) {
            htmlHeader.writeln("<link rel='import' href='${template}'>");
          }
        }
        continue;
      }

      DartObject behavior = getAnnotation(m.element.metadata, isPolymerBehavior);
      if (behavior!=null) {
        String name = behavior.getField('name').toStringValue();
        code_builder.ReferenceBuilder cls = code_builder.reference(classElement.name,ctx.inputUri);

        code_builder.ExpressionBuilder configExpressionBuilder = collectConfig(libBuilder, ctx.ctx.analysisContext, classElement);

        initModuleBuilder.addStatement(defBehavior.call([code_builder.literal(name),cls,configExpressionBuilder]));
      }
    }
  }
}

code_builder.ExpressionBuilder collectConfig(code_builder.LibraryBuilder libBuilder, AnalysisContext context, ClassElement ce) {
  code_builder.TypeBuilder configType = new code_builder.TypeBuilder("Config",importFrom: POLYMERIZE_JS);


  code_builder.ReferenceBuilder jsifyRef = code_builder.reference('jsify', JS_UTIL);

  code_builder.TypeBuilder propertyType = new code_builder.TypeBuilder("Property",importFrom: POLYMERIZE_JS);
  code_builder.TypeBuilder reduxPropertyType = new code_builder.TypeBuilder("ReduxProperty",importFrom: POLYMERIZE_JS);

  List<code_builder.ExpressionBuilder> observers = [];
  List<code_builder.ExpressionBuilder> reduxActions = [];
  Map<String, code_builder.ExpressionBuilder> properties = {};

  ce.methods.forEach((MethodElement me) {
    DartObject obs = getAnnotation(me.metadata, isObserve);
    if (obs != null) {
      String params = obs.getField('observed').toStringValue();

      observers.add(code_builder.literal("${me.name}(${params})"));
      return;
    }
    obs = getAnnotation(me.metadata, isReduxActionFactory);
    if (obs != null) {
      reduxActions.add(code_builder.literal(me.name));
    }
  });

  ce.fields.forEach((FieldElement fe) {
    DartObject not = getAnnotation(fe.metadata, isNotify);
    bool notify;
    String statePath;
    notify = not != null;
    DartObject prop = getAnnotation(fe.metadata, isProperty);
    if (prop != null) {
      notify = prop.getField('notify').toBoolValue();
      statePath = prop.getField('statePath').toStringValue();
    }

    if (statePath!=null) {
      properties[fe.name] = reduxPropertyType.newInstance([], named: {'notify': code_builder.literal(notify), 'statePath': code_builder.literal(statePath)});
    } else {
      properties[fe.name] = propertyType.newInstance([], named: {'notify': code_builder.literal(notify)});
    }

  });

  String behaviorName(ClassElement intf, DartObject anno) {
    DartObject libAnno = getAnnotation(intf.library.metadata, isJS);
    String res = anno.getField('name').toStringValue();
    if (libAnno == null) {
      return res;
    } else {
      String pkg = libAnno.getField('name').toStringValue();
      return "${pkg}.${res}";
    }
  }

  Set<code_builder.ExpressionBuilder> behaviors = new Set()
    ..addAll(ce.interfaces.map((InterfaceType intf) {
      DartObject anno = getAnnotation(intf.element.metadata, anyOf([isPolymerBehavior, isJS]));
      if (anno != null) {
        return code_builder.literal(behaviorName(intf.element, anno));
      } else {
        return null;
      }
    }).where(notNull));

  return configType.newInstance([], named: {
    'observers': code_builder.list(observers),
    'properties': jsifyRef.call([code_builder.map(properties)]),
    'reduxActions': code_builder.list(reduxActions),
    'behaviors': code_builder.list(behaviors),
    'reduxInfo': reduxInfoBuilder(libBuilder, context, ce)
  });
}

int count = 0;

code_builder.ExpressionBuilder reduxInfoBuilder(code_builder.LibraryBuilder libBuilder, AnalysisContext ctx, ClassElement ce) {
  code_builder.TypeBuilder reduxInfoRef = new code_builder.TypeBuilder("ReduxInfo",importFrom: POLYMERIZE_JS);


  return ce.interfaces.map((intf) {
    ElementAnnotation anno = getElementAnnotation(intf.element.metadata, isStoreDef);
    if (anno == null) {
      return null;
    }

    //print("${anno.element.kind}");
    if (anno.element.kind == ElementKind.GETTER) {
      MethodElement m = anno.element;
      //print(
      //    "GETTER: ${m.name}, ${mod},${m.source.shortName}, path:${p}");

      return reduxInfoRef.newInstance([], named: {'reducer': code_builder.reference(m.name,m.source.uri.toString()).property('reducer')});
    } else {
      /**
          DartObject reducer = anno.computeConstantValue().getField('reducer');
          return reducer;
       */
      return null;
    }
  }).firstWhere(notNull, orElse: () => reduxInfoRef.newInstance([]));
}

Future _addHtmlImport(GeneratorContext ctx, CompilationUnit cu, code_builder.LibraryBuilder libBuilder, code_builder.MethodBuilder initModuleBuilder, IOSink htmlHeader) async =>
    allFirstLevelAnnotation(cu, isHtmlImport).map((o) => o.getField('path').toStringValue()).forEach((relPath) => htmlHeader.writeln("<link rel='import' href='${relPath}'>"));
