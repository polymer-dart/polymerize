import 'dart:io';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';

final Uri POLYMER_REGISTER_URI = Uri.parse('package:polymer_element/polymer_element.dart');
final Uri POLYMER_REGISTER_ASSET_URI = Uri.parse('asset:polymer_element/lib/polymer_element.dart');
final Uri JS_URI = Uri.parse('package:js/js.dart');
final Uri JS_ASSET_URI = Uri.parse('asset:js/lib/js.dart');

bool isJsUri(Uri u) => u == JS_ASSET_URI || u == JS_URI;

bool isPolymerElementUri(Uri u) => u == POLYMER_REGISTER_ASSET_URI || u == POLYMER_REGISTER_URI;

bool isJS(DartObject o) => (isJsUri(o.type.element.librarySource.uri)) && (o.type.name == 'JS');

bool isBowerImport(DartObject o) => (isPolymerElementUri(o.type.element.librarySource.uri)) && (o.type.name == 'BowerImport');

bool isDefine(DartObject o) => (isPolymerElementUri(o.type.element.librarySource.uri)) && (o.type.name == 'Define');

bool isObserve(DartObject o) => (isPolymerElementUri(o.type.element.librarySource.uri)) && (o.type.name == 'Observe');

bool isReduxActionFactory(DartObject o) => (isPolymerElementUri(o.type.element.librarySource.uri)) && (o.type.name == 'ReduxActionFactory');

bool isProperty(DartObject o) => (isPolymerElementUri(o.type.element.librarySource.uri)) && (o.type.name == 'Property');

bool isNotify(DartObject o) => (isPolymerElementUri(o.type.element.librarySource.uri)) && (o.type.name == 'Notify');

bool isPolymerRegister(DartObject o) => (isPolymerElementUri(o.type.element.librarySource.uri)) && (o.type.name == 'PolymerRegister');

bool isPolymerBehavior(DartObject o) => (isPolymerElementUri(o.type.element.librarySource.uri)) && (o.type.name == 'PolymerBehavior');

bool isStoreDef(DartObject o) => (isPolymerElementUri(o.type.element.librarySource.uri)) && (o.type.name == 'StoreDef');

DartObject getAnnotation(
        Iterable<ElementAnnotation> metadata, //
        bool matches(DartObject x)) =>
    metadata.map((an) => an.computeConstantValue()).firstWhere(matches, orElse: () => null);

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
