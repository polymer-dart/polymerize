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

List<CodeGenerator> _codeGenerators = [_generateInitMethods, _generatePolymerRegister, _addHtmlImport];

class GeneratorContext {
  InternalContext ctx;
  String inputUri;
  String genPath;

  CompilationUnit cu;
  code_builder.LibraryBuilder libBuilder;
  code_builder.MethodBuilder _initModuleBuilder;
  IOSink _htmlHeader;
  code_builder.Scope scope;

  void addImportHtml(String path) {
    _htmlHeader.writeln("<link rel='import' href='${path}'>");
  }

  GeneratorContext(this.ctx, this.inputUri, this._htmlHeader, this.genPath) {
    cu = ctx.getCompilationUnit(inputUri);

    scope = new code_builder.Scope.dedupe();
    libBuilder = new code_builder.LibraryBuilder.scope(scope: scope);
    _initModuleBuilder = new code_builder.MethodBuilder("initModule");
    libBuilder.addMember(_initModuleBuilder);
  }

  Future _finish() async {
    _initModuleBuilder.addStatement(code_builder.returnVoid);

    return new File(genPath).writeAsString(code_builder.prettyToSource(libBuilder.buildAst(scope)));
  }

  Future generateCode() async {
    await Future.wait(_codeGenerators.map((gen) => gen(this)));
    return _finish();
  }

  void addInitStatement(code_builder.StatementBuilder statement) {
    _initModuleBuilder.addStatement(statement);
  }
}

Future generateCode(String inputUri, String genPath, IOSink htmlTemp) async {
  InternalContext ctx = await InternalContext.create('.');
  ctx.invalidateUri(inputUri);
  GeneratorContext getctx = new GeneratorContext(ctx, inputUri, htmlTemp, genPath);

  return getctx.generateCode();
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

          // TODO : add support for template static getter too ...
          if (template != null) {
            // Read the template to check for properties that need to be observed
            String sourcePath = await ctx.ctx.resolvePackageUri(Uri.parse(ctx.inputUri));
            String dirPath = path.dirname(sourcePath);
            String templatePath = path.join(dirPath, template);

            if (await new File(templatePath).exists()) {
              // Read and process the template
              HtmlDocResume htmlDocResume = _analyzeHtmlTemplate(ctx, templatePath);
              // Now set the code that will register those info in order
              // To make it available to eventually the observer behavior
              ctx.addInitStatement(metadataRegRef.invoke('registerMetadata', [
                code_builder.literal(tagName),
                metadataRef.newInstance([], named: {"observedPaths": code_builder.list(htmlDocResume.propertyPaths)})
              ]));
            }
          }

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

          DartObject libraryAnnotation = getAnnotation(classElement.library.metadata, isJS).getField('name');
          module = libraryAnnotation.toStringValue();
          DartObject classAnno = getAnnotation(classElement.metadata, isJS).getField('name');
          className = classAnno.isNull ? classElement.name : classAnno.toStringValue();

          ctx.addInitStatement(importNativeRef.call([
            code_builder.literal(tagName),
            code_builder.list([module, className].map((x) => code_builder.literal(x)))
          ]));
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

  code_builder.TypeBuilder propertyType = new code_builder.TypeBuilder("Property", importFrom: POLYMERIZE_JS);
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
    DartObject prop = getAnnotation(fe.metadata, isProperty);
    if (prop != null) {
      notify = prop.getField('notify').toBoolValue();
      statePath = prop.getField('statePath').toStringValue();
    }

    if (statePath != null) {
      properties[fe.name] = reduxPropertyType.newInstance([], named: {'notify': code_builder.literal(notify), 'statePath': code_builder.literal(statePath)});
    } else {
      properties[fe.name] = propertyType.newInstance([], named: {'notify': code_builder.literal(notify)});
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

int count = 0;

Future _addHtmlImport(GeneratorContext ctx) async =>
    allFirstLevelAnnotation(ctx.cu, isHtmlImport).map((o) => o.getField('path').toStringValue()).forEach((relPath) => ctx.addImportHtml(relPath));

/***
 * Analyze one HTML template
 */

class HtmlDocResume {
  Set<String> propertyPaths = new Set();
  Set<String> eventHandlers = new Set();
  Set<String> customElementsRefs = new Set();

  toString() => "props : ${propertyPaths} , events : ${eventHandlers}, ele : ${customElementsRefs}";
}

class Options {
  bool polymerize_imported = false;
  bool native_imported = false;
}

HtmlDocResume _analyzeHtmlTemplate(GeneratorContext genctx, String templatePath) {
  HtmlDocResume resume = new HtmlDocResume();
  Source source = genctx.ctx.analysisContext.sourceFactory.forUri(path.toUri(templatePath).toString());
  dom.Document doc = genctx.ctx.analysisContext.parseHtmlDocument(source);
  dom.Element domElement = doc.querySelector('dom-module');
  if (domElement == null) {
    return resume;
  }
  dom.Element templateElement = domElement.querySelector('template');
  if (templateElement == null) {
    return resume;
  }

  // Lookup all the refs
  _extractRefs(resume, templateElement);

  return resume;
}

_extractRefs(HtmlDocResume resume, dom.Element element) {
  if (element.localName.contains('-')) {
    resume.customElementsRefs.add(element.localName);
  }
  element.attributes.keys.forEach((k) {
    String val = element.attributes[k];
    if (k.startsWith('on-')) {
      resume.eventHandlers.add(val);
    } else {
      // Check for prop refs
      resume.propertyPaths.addAll(_extractRefsFromString(val));
    }
  });

  _extractRefsFromString(element.text);

  element.children.forEach((el) => _extractRefs(resume, el));
}

final RegExp _propRefRE = new RegExp(r"(\{\{|\[\[)!?([^}]+)(\}\}|\]\])");

final RegExp _funcCallRE = new RegExp(r'([^()]+)\(([^)]+)\)');

Iterable<String> _extractRefsFromString(String element) => _propRefRE.allMatches(element).map((x) => x.group(2));
