import 'dart:async';
import 'dart:convert';

import 'dart:io';
import 'package:analyzer/analyzer.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:barback/barback.dart';
import 'package:code_transformers/resolver.dart';
import 'package:polymerize/src/code_generator.dart';
import 'package:polymerize/src/dart_file_command.dart';
import 'package:polymerize/src/dep_analyzer.dart';

import 'package:path/path.dart' as p;

class ResolversInternalContext implements InternalContext {
  Resolver _resolver;

  static AssetId toAssetId(String uriString) {
    Uri uri = Uri.parse(uriString);
    if (uri.scheme == 'package') {
      AssetId assetId = new AssetId(uri.pathSegments[0], "lib/${uri.pathSegments.sublist(1).join("/")}");
      return assetId;
    }
    throw "Unknown URI ${uriString}";
  }

  ResolversInternalContext(Resolver resolver) : _resolver = resolver;

  @override
  CompilationUnit getCompilationUnit(String inputUri) => getLibraryElement(inputUri).unit;

  @override
  LibraryElement getLibraryElement(String inputUri) => _resolver.getLibrary(toAssetId(inputUri));

  @override
  void invalidateUri(String inputUri) {
    // Nothing to do here
  }
}

const String ORIG_EXT = "_orig.dart";

class PrepareTransformer extends Transformer with ResolverTransformer {
  PrepareTransformer({bool releaseMode, this.settings}) {
    resolvers = new Resolvers(dartSdkDirectory);
  }
  BarbackSettings settings;

  PrepareTransformer.asPlugin(BarbackSettings settings) : this(releaseMode: settings.mode == BarbackMode.RELEASE, settings: settings);

  Future<bool> isPrimary(id) async {
    return id.extension == '.dart' && id.path.startsWith("lib/");
  }

  @override
  applyResolver(Transform transform, Resolver resolver) async {
    if (!resolver.isLibrary(transform.primaryInput.id)) {
      transform.logger.fine("${transform.primaryInput.id} is NOT a library, skipping");
      return;
    }
    AssetId origId = transform.primaryInput.id.changeExtension(ORIG_EXT);
    Stream<List<int>> content = transform.primaryInput.read();
    Asset orig = new Asset.fromStream(origId, content);
    transform.addOutput(orig);
    transform.consumePrimary();
    transform.logger.fine("COPY ${transform.primaryInput.id} INTO ${origId} WITH CONTENT : ${content}", asset: origId);
    transform.logger.fine("ADDED : ${orig}", asset: origId);
  }

  @override
  Future<bool> shouldApplyResolver(Asset asset) async {
    return asset.id.extension == ".dart";
  }
}

class InoculateTransformer extends Transformer with ResolverTransformer implements DeclaringTransformer {
  InoculateTransformer({bool releaseMode, this.settings}) {
    resolvers = new Resolvers(dartSdkDirectory);
  }
  BarbackSettings settings;

  InoculateTransformer.asPlugin(BarbackSettings settings) : this(releaseMode: settings.mode == BarbackMode.RELEASE, settings: settings);

  Future<bool> isPrimary(id) async {
    return id.path.endsWith(ORIG_EXT) && id.path.startsWith("lib/");
  }

  AssetId toDest(AssetId orig) => new AssetId(orig.package, orig.path.substring(0, orig.path.length - ORIG_EXT.length) + ".dart");
  AssetId toHtmlDest(AssetId orig) => toDest(orig).changeExtension('.mod.html');

  @override
  declareOutputs(DeclaringTransform transform) {
    // for each dart file produce a '.g.dart'

    transform.declareOutput(toDest(transform.primaryId));
    transform.declareOutput(toHtmlDest(transform.primaryId));
  }

  @override
  applyResolver(Transform transform, Resolver resolver) async {
    Buffer outputBuffer = new Buffer();
    Buffer htmlBuffer = new Buffer();

    AssetId origId = transform.primaryInput.id;
    AssetId dest = toDest(origId);
    transform.logger.fine("DEST ID : ${dest}");

    String basePath = p.joinAll(p.split(origId.path).sublist(1));
    String uri = "package:${origId.package}/${basePath}";
    transform.logger.fine("My URI : :${uri}");

    GeneratorContext generatorContext = new GeneratorContext(new ResolversInternalContext(resolver), uri, htmlBuffer.createSink(), outputBuffer.createSink());
    await generatorContext.generateCode();
    Asset gen = new Asset.fromStream(dest, outputBuffer.binaryStream);
    transform.addOutput(gen);
    //transform.logger.info("GEN ${dest}: ${await gen.readAsString()}");

    AssetId htmlId = toHtmlDest(transform.primaryInput.id);

    Asset html = new Asset.fromStream(htmlId, htmlBuffer.stream.transform(UTF8.encoder));
    transform.addOutput(html);
    transform.logger.fine("HTML : ${htmlId}");
  }

  @override
  Future<bool> shouldApplyResolver(Asset asset) async {
    return asset.id.path.endsWith('.dart');
  }
}
