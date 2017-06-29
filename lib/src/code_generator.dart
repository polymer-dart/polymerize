import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:analyzer/analyzer.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/source.dart';
import 'package:code_builder/code_builder.dart' as code_builder;

import 'package:html/dom.dart' as dom;
import 'package:polymerize/src/dep_analyzer.dart';
import 'package:polymerize/src/utils.dart';
import 'package:path/path.dart' as path;

typedef Future CodeGenerator(GeneratorContext ctx);

List<CodeGenerator> _codeGenerators = [_generateInitMethods, _generatePolymerRegister, _addHtmlImport, _generateForceImport];

class GeneratorContext {
  InternalContext ctx;
  String inputUri;
  IOSink output;

  CompilationUnit cu;
  code_builder.PartOfBuilder libBuilder;
  code_builder.MethodBuilder _initModuleBuilder;
  IOSink _htmlHeader;
  code_builder.Scope scope;

  void addImportHtml(String path) {
    _htmlHeader.writeln("<link rel='import' href='${path}'>");
  }

  //List<code_builder.ReferenceBuilder> _refs = [];

  GeneratorContext(this.ctx, this.inputUri, this._htmlHeader, this.output) {
    cu = ctx.getCompilationUnit(inputUri);

    scope = new code_builder.Scope.dedupe();

    libBuilder = new code_builder.PartOfBuilder(inputUri, scope);

    code_builder.ReferenceBuilder ref = code_builder.reference('initModule', 'package:polymerize_common/init.dart');
    //libBuilder.addAnnotation(ref);
    _initModuleBuilder = new code_builder.MethodBuilder("generatedInitModule");
    libBuilder.addMember(_initModuleBuilder);
    _initModuleBuilder.addAnnotation(ref);
  }

  Future<List<code_builder.ImportBuilder>> _finish() async {
    _initModuleBuilder.addStatement(code_builder.returnVoid);
    //libBuilder.addMember(code_builder.list(_refs).asFinal('_refs'));

    output.write(code_builder.prettyToSource(libBuilder.buildAst(scope)));
    await Future.wait([output.flush(), _htmlHeader.flush()]);

    return scope.toImports();
  }

  Future<List<code_builder.ImportBuilder>> generateCode() async {
    //libBuilder.addDirective(new code_builder.ExportBuilder(inputUri));
    //libBuilder.addDirective(new code_builder.ImportBuilder(inputUri,prefix: 'orig'));
    await Future.wait(_codeGenerators.map((gen) => gen(this)));
    return _finish();
  }

  void addInitStatement(code_builder.StatementBuilder statement) {
    _initModuleBuilder.addStatement(statement);
  }

  //void addRef(code_builder.ReferenceBuilder cls) {
  //  _refs.add(cls);
  //}
}

Future generateCode(String inputUri, String genPath, IOSink htmlTemp) async {
  InternalContext ctx = await InternalContext.create('.');
  ctx.invalidateUri(inputUri);

  File f = new File(genPath);
  IOSink s = f.openWrite();
  GeneratorContext getctx = new GeneratorContext(ctx, inputUri, htmlTemp, s);
  await getctx.generateCode();
  await s.close();
}

/**
 * Look for INIT METHODS
 */

Future _generateInitMethods(GeneratorContext ctx) async {
  for (CompilationUnitMember m in ctx.cu.declarations) {
    if (m.element?.kind == ElementKind.FUNCTION) {
      FunctionElement functionElement = m.element;
      DartObject init = getAnnotation(m.element.metadata, isInit);
      if (init != null && functionElement.parameters.isEmpty) {
        code_builder.ReferenceBuilder ref = code_builder.reference(functionElement.name, ctx.inputUri);
        ctx.addInitStatement(ref.call([]));
      }
    }
  }
}

/**
 * Check if importing a native lib that contains annotations that needs be imported.
 */

String forceFlagName(LibraryElement le, [String prefix]) => "${prefix!=null?prefix+'.':''}FORCE_${le.source.uri.toString().replaceAll(new RegExp('[._:/-]'),'_')}";

Future _generateForceImport(GeneratorContext ctx) async {
  code_builder.ExpressionBuilder expressionBuilder = code_builder.literal(false);
  for (ImportElement ie in ctx.cu.element.library.imports) {
    if (needsProcessing(ie.importedLibrary)) {
      expressionBuilder = expressionBuilder.or(code_builder.reference(forceFlagName(ie.importedLibrary, ie.prefix?.name), ie.importedLibrary.source.uri.toString()));
    }
  }
  ctx.libBuilder.addMember(expressionBuilder.asFinal(forceFlagName(ctx.cu.element.library)));
}

const String POLYMERIZE_JS = 'package:polymer_element/polymerize_js.dart';
const String MEDATADATA_REG_JS = 'package:polymer_element/metadata_registry.dart';
const String JS_UTIL = 'package:js/js_util.dart';

Future _generatePolymerRegister(GeneratorContext ctx) async {
  //code_builder.TypeBuilder summaryType = new code_builder.TypeBuilder('Summary', importFrom: POLYMERIZE_JS);

  code_builder.ReferenceBuilder metadataRegRef = code_builder.reference("metadataRegistry", MEDATADATA_REG_JS);

  code_builder.TypeBuilder metadataRef = new code_builder.TypeBuilder("Metadata", importFrom: MEDATADATA_REG_JS);

  code_builder.ReferenceBuilder ref = code_builder.reference("register", POLYMERIZE_JS);

  code_builder.ReferenceBuilder importNativeRef = code_builder.reference("importNative", POLYMERIZE_JS);

  code_builder.ReferenceBuilder defBehavior = code_builder.reference("defineBehavior", POLYMERIZE_JS);

  code_builder.ReferenceBuilder summaryFactory = code_builder.reference("summary", POLYMERIZE_JS);

  // lookup for annotation
  for (CompilationUnitMember m in ctx.cu.declarations) {
    if (m.element?.kind == ElementKind.CLASS) {
      ClassElement classElement = m.element;
      DartObject register = getAnnotation(m.element.metadata, isPolymerRegister);
      if (register != null) {
        String tagName = register.getField('tagName').toStringValue();
        String template = register.getField('template').toStringValue();
        bool native = register.getField('native').toBoolValue();

        if (!native) {
          code_builder.ReferenceBuilder cls = code_builder.reference(classElement.name, ctx.inputUri);
          //ctx.addRef(cls);

          code_builder.ExpressionBuilder configExpressionBuilder = collectConfig(ctx, classElement);

          ctx.addInitStatement(
              ref.call([cls, code_builder.literal(tagName), configExpressionBuilder, summaryFactory.call([]), code_builder.literal(false), code_builder.literal(template)]));
          if (template != null) {
            ctx.addImportHtml(template);
          }
        } else {
          // Import native (define a class if it doesn't exist

          String module;
          String className;

          //ctx.addRef(code_builder.reference(classElement.name,ctx.inputUri));

          DartObject libraryAnnotation = getAnnotation(classElement.library.metadata, isJS)?.getField('name');
          if (libraryAnnotation != null) {
            module = libraryAnnotation.toStringValue();
            DartObject classAnno = getAnnotation(classElement.metadata, isJS).getField('name');
            className = classAnno.isNull ? classElement.name : classAnno.toStringValue();

            ctx.addInitStatement(importNativeRef.call([
              code_builder.literal(tagName),
              code_builder.list([module, className].map((x) => code_builder.literal(x)))
            ]));
          }
        }
        continue;
      }

      DartObject behavior = getAnnotation(m.element.metadata, isPolymerBehavior);
      if (behavior != null) {
        String name = _behaviorName(m.element, behavior);
        code_builder.ReferenceBuilder cls = code_builder.reference(classElement.name, ctx.inputUri);

        code_builder.ExpressionBuilder configExpressionBuilder = collectConfig(ctx, classElement);

        ctx.addInitStatement(defBehavior.call([code_builder.literal(name), cls, configExpressionBuilder]));
      }
    }
  }
}

String _behaviorName(ClassElement intf, DartObject anno) {
  DartObject libAnno = getAnnotation(intf.library.metadata, isJS);
  String res = anno.getField('name').toStringValue();
  if (libAnno == null || libAnno.getField('name').isNull) {
    return res;
  } else {
    String pkg = libAnno.getField('name').toStringValue();
    return "${pkg}.${res}";
  }
}

code_builder.ExpressionBuilder collectConfig(GeneratorContext genctx, ClassElement ce) {
  code_builder.TypeBuilder configType = new code_builder.TypeBuilder("Config", importFrom: POLYMERIZE_JS);

  code_builder.ReferenceBuilder jsifyRef = code_builder.reference('jsify', JS_UTIL);

  code_builder.TypeBuilder propertyType = new code_builder.TypeBuilder("PolymerProperty", importFrom: POLYMERIZE_JS);
  code_builder.TypeBuilder reduxPropertyType = new code_builder.TypeBuilder("ReduxProperty", importFrom: POLYMERIZE_JS);

  code_builder.ReferenceBuilder resolveJs = code_builder.reference('resolveJsObject', POLYMERIZE_JS);

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
    String computed;
    DartObject prop = getAnnotation(fe.metadata, isProperty);
    if (prop != null) {
      notify = prop.getField('notify').toBoolValue();
      computed = prop.getField('computed').toStringValue();
      statePath = prop.getField('statePath').toStringValue();
    }

    if (statePath != null) {
      properties[fe.name] = reduxPropertyType.newInstance([], named: {'notify': code_builder.literal(notify), 'statePath': code_builder.literal(statePath)});
    } else {
      properties[fe.name] = propertyType.newInstance([], named: {'notify': code_builder.literal(notify), 'computed': code_builder.literal(computed)});
    }
  });

  Set<code_builder.ExpressionBuilder> behaviors = new Set()
    ..addAll(ce.interfaces.map((InterfaceType intf) {
      DartObject anno = getAnnotation(intf.element.metadata, anyOf([isPolymerBehavior, isJS]));
      if (anno != null) {
        return resolveJs.call([code_builder.literal(_behaviorName(intf.element, anno))]);
      } else {
        return null;
      }
    }).where(notNull));

  return configType.newInstance([], named: {
    'observers': code_builder.list(observers),
    'properties': jsifyRef.call([code_builder.map(properties)]),
    'reduxActions': code_builder.list(reduxActions),
    'behaviors': code_builder.list(behaviors)
  });
}

Future _addHtmlImport(GeneratorContext ctx) async =>
    allFirstLevelAnnotation([ctx.cu], isHtmlImport).map((o) => o.getField('path').toStringValue()).forEach((relPath) => ctx.addImportHtml(relPath));
