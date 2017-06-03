import 'dart:io';
import 'package:analyzer/analyzer.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';

final Uri _POLYMER_REGISTER_URI = Uri.parse('package:polymer_element/annotations.dart');
final Uri _POLYMER_REGISTER_ASSET_URI = Uri.parse('asset:polymer_element/lib/annotations.dart');
final Uri _JS_URI = Uri.parse('package:js/js.dart');
final Uri _JS_ASSET_URI = Uri.parse('asset:js/lib/js.dart');

final Uri _POLYMER_INIT_URI = Uri.parse('package:polymerize_common/init.dart');
final Uri _POLYMER_INIT_ASSET_URI = Uri.parse('asset:polymerize_common/lib/init.dart');

final Uri _POLYMER_HTML_IMPORT_URI = Uri.parse('package:polymerize_common/html_import.dart');
final Uri _POLYMER_HTML_IMPORT_ASSET_URI = Uri.parse('asset:polymerize_common/lib/html_import.dart');

bool isJsUri(Uri u) => u == _JS_ASSET_URI || u == _JS_URI;

bool isPolymerElementUri(Uri u) => u == _POLYMER_REGISTER_ASSET_URI || u == _POLYMER_REGISTER_URI;

bool isPolymerElementInitUri(Uri u) => u == _POLYMER_INIT_URI || u == _POLYMER_INIT_ASSET_URI;

bool isPolymerElementHtmlImportUri(Uri u) => u == _POLYMER_HTML_IMPORT_URI || u == _POLYMER_HTML_IMPORT_ASSET_URI;

bool isJS(DartObject o) => (isJsUri(o.type.element.librarySource.uri)) && (o.type.name == 'JS');

bool isBowerImport(DartObject o) => o != null && (isPolymerElementUri(o.type.element.librarySource.uri)) && (o.type.name == 'BowerImport');

bool isDefine(DartObject o) => (isPolymerElementUri(o.type.element.librarySource.uri)) && (o.type.name == 'Define');

bool isObserve(DartObject o) => (isPolymerElementUri(o.type.element.librarySource.uri)) && (o.type.name == 'Observe');

bool isReduxActionFactory(DartObject o) => (isPolymerElementUri(o.type.element.librarySource.uri)) && (o.type.name == 'ReduxActionFactory');

bool isProperty(DartObject o) => (isPolymerElementUri(o.type.element.librarySource.uri)) && (o.type.name == 'Property');

bool isNotify(DartObject o) => (isPolymerElementUri(o.type.element.librarySource.uri)) && (o.type.name == 'Notify');

bool isPolymerRegister(DartObject o) => o != null && (isPolymerElementUri(o.type.element.librarySource.uri)) && (o.type.name == 'PolymerRegister');

bool isPolymerBehavior(DartObject o) => (isPolymerElementUri(o.type.element.librarySource.uri)) && (o.type.name == 'PolymerBehavior');

bool isStoreDef(DartObject o) => (isPolymerElementUri(o.type.element.librarySource.uri)) && (o.type.name == 'StoreDef');

bool isInit(DartObject o) => o != null && (isPolymerElementInitUri(o.type.element.librarySource.uri)) && (o.type.name == 'Init');

bool isHtmlImport(DartObject o) => o != null && (isPolymerElementHtmlImportUri(o.type.element.librarySource.uri)) && (o.type.name == 'HtmlImport');

Iterable<DartObject> allFirstLevelAnnotation(CompilationUnit cu, bool matches(DartObject x)) =>
    cu.sortedDirectivesAndDeclarations
      .map(_element)
      .where(_isNotNull)
      .map((e) => e.metadata)
      .where(_isNotNull)
      .map((anno) => getAnnotation(anno, matches)).where(_isNotNull);


Element _element(AstNode x) => (x is Declaration) ? x.element : ((x is Directive) ? x.element : null);

bool _isNotNull(x) => x != null;

bool hasAnyFirstLevelAnnotation(CompilationUnit cu, bool matches(DartObject x)) => allFirstLevelAnnotation(cu,matches).isNotEmpty;

DartObject getAnnotation(
        Iterable<ElementAnnotation> metadata, //
        bool matches(DartObject x)) =>
    metadata.map((an) => an.computeConstantValue()).where(notNull).firstWhere(matches, orElse: () => null);

ElementAnnotation getElementAnnotation(
        Iterable<ElementAnnotation> metadata, //
        bool matches(DartObject x)) =>
    metadata.firstWhere((an) => matches(an.computeConstantValue()), orElse: () => null);

Directory findDartSDKHome() {
  if (Platform.environment['DART_HOME'] != null) {
    return new Directory(Platform.environment['DART_HOME']);
  }

  //print("res:${Platform.resolvedExecutable} exe:${Platform.executable} root:${Platform.packageRoot} cfg:${Platform.packageConfig} ");
  // Else tries with current executable
  return new File(Platform.resolvedExecutable).parent;
}

typedef bool matcher(DartObject x);

matcher anyOf(List<matcher> matches) => (DartObject o) => matches.any((m) => m(o));

bool notNull(x) => x != null;
