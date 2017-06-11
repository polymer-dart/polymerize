import 'dart:async';
import 'dart:convert';

import 'dart:core';
import 'dart:io';
import 'package:analyzer/analyzer.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:barback/barback.dart';
import 'package:code_transformers/resolver.dart';
import 'package:glob/glob.dart';
import 'package:polymerize/src/code_generator.dart';
import 'package:polymerize/src/dart_file_command.dart';
import 'package:polymerize/src/dep_analyzer.dart';
import 'package:code_builder/code_builder.dart';
import 'package:resource/resource.dart';

import 'package:path/path.dart' as p;
import 'package:polymerize/src/utils.dart';

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

const String ORIG_EXT = ".dart";

Iterable<Uri> _findDependencies(Transform t, Resolver r) => _findDependenciesFor(t, r, r.getLibrary(t.primaryInput.id));

Iterable<LibraryElement> _libraryTree(LibraryElement from, [Set<LibraryElement> traversed]) sync* {
  if (traversed == null) {
    traversed = new Set<LibraryElement>();
  }

  if (traversed.contains(from)) {
    return;
  }
  traversed.add(from);
  yield from;
  for (LibraryElement lib in _referencedLibs(from)) {
    yield* _libraryTree(lib, traversed);
  }
}

bool _anyDepNeedsHtmlImport(LibraryElement lib) => _libraryTree(lib).any(_needsHtmlImport);

Iterable<LibraryElement> _referencedLibs(LibraryElement lib) sync* {
  yield* lib.imports.map((i) => i.importedLibrary);
  yield* lib.exports.map((e) => e.exportedLibrary);
}

Iterable<Uri> _findDependenciesFor(Transform t, Resolver r, LibraryElement lib) =>
    _referencedLibs(lib).where(_anyDepNeedsHtmlImport).map((lib) => r.getImportUri(lib, from: t.primaryInput.id));

class InoculateTransformer extends Transformer with ResolverTransformer {
  InoculateTransformer({bool releaseMode, this.settings}) {
    resolvers = new Resolvers(dartSdkDirectory);
  }
  BarbackSettings settings;

  InoculateTransformer.asPlugin(BarbackSettings settings) : this(releaseMode: settings.mode == BarbackMode.RELEASE, settings: settings);

  Future<bool> isPrimary(id) async {
    return id.path.endsWith(ORIG_EXT) && id.path.startsWith("lib/");
  }

  AssetId toDest(AssetId orig) => new AssetId(orig.package, orig.path.substring(0, orig.path.length - ORIG_EXT.length) + "_g.dart");

  @override
  declareOutputs(DeclaringTransform transform) {
    // for each dart file produce a '.g.dart'

    transform.declareOutput(toDest(transform.primaryId));
    //transform.declareOutput(toHtmlDest(transform.primaryId));
  }

  @override
  applyResolver(Transform transform, Resolver resolver) async {
    if (!resolver.isLibrary(transform.primaryInput.id) || !needsProcessing(resolver.getLibrary(transform.primaryInput.id))) {
      transform.logger.fine("${transform.primaryInput.id} is NOT a library, skipping");
      return;
    }

    transform.logger.fine("Processing ${transform.primaryInput.id}");
    Buffer outputBuffer = new Buffer();
    Buffer htmlBuffer = new Buffer();

    AssetId origId = transform.primaryInput.id;
    AssetId dest = toDest(origId);
    transform.logger.fine("DEST ID : ${dest}");

    String basePath = p.joinAll(p.split(origId.path).sublist(1));
    String uri; // = "package:${origId.package}/${basePath}";

    uri = resolver.getImportUri(resolver.getLibrary(origId), from: dest).toString();
    transform.logger.fine("My URI : :${uri}");

    GeneratorContext generatorContext = new GeneratorContext(new ResolversInternalContext(resolver), uri, htmlBuffer.createSink(), outputBuffer.createSink());
    await generatorContext.generateCode();
    Asset gen = new Asset.fromStream(dest, outputBuffer.binaryStream);
    transform.addOutput(gen);

    transform.logger.fine("PRODUCED : ${await gen.readAsString()}");

    // add a line at the endbeginning
    String myFile = (await transform.primaryInput.readAsString());
    int pos;
    List<Declaration> decls = resolver.getLibrary(transform.primaryInput.id).unit.declarations;
    if (decls.isEmpty) {
      pos = myFile.length;
    } else {
      // find first part
      List<Directive> ris = resolver.getLibrary(transform.primaryInput.id).unit.directives ?? [];

      PartDirective firstPart = ris.firstWhere((d) => d is PartDirective, orElse: () => null);
      if (firstPart != null) {
        pos = firstPart.offset;
      } else {
        pos = decls.first.offset;
      }
    }

    Asset replacing = new Asset.fromStream(
        transform.primaryInput.id,
        () async* {
          yield myFile.substring(0, pos);
          yield "/* POLYMERIZED ( */";
          yield "part '${p.basename(dest.path)}';";
          yield "/* ) POLYMERIZED */";
          yield myFile.substring(pos);
        }()
            .transform(UTF8.encoder));
    transform.logger.fine("REPLACING : ${await replacing.readAsString()}");
    transform.addOutput(replacing);

    transform.logger.fine("PROCESSED ${transform.primaryInput.id}");
  }

  @override
  Future<bool> shouldApplyResolver(Asset asset) async {
    return asset.id.path.endsWith('.dart');
  }
}

class FinalizeTransformer extends Transformer with ResolverTransformer {
  FinalizeTransformer({bool releaseMode, this.settings}) {
    resolvers = new Resolvers(dartSdkDirectory);
  }
  BarbackSettings settings;

  FinalizeTransformer.asPlugin(BarbackSettings settings) : this(releaseMode: settings.mode == BarbackMode.RELEASE, settings: settings);

  Future<bool> isPrimary(id) async {
    return settings.configuration.containsKey('entry-point')&& new Glob(settings.configuration['entry-point']).matches(id.path);
  }

  @override
  applyResolver(Transform transform, Resolver resolver) async {
    // generate bower.json
    if (!settings.configuration.containsKey('entry-point')) {
      return;
    }

    transform.logger.fine("GENERATING BOWER.JSON WITH ${settings.configuration}", asset: transform.primaryInput.id);

    await _generateBowerJson(transform, resolver);
  }

  Future _generateBowerJson(Transform t, Resolver r) async {
    // Check if current lib matches

    t.logger.fine("PRODUCING BOWER.JSON FOR ${t.primaryInput.id}");

    // Create bower.json and collect all extra deps

    Map<String, Set<String>> extraDeps = {};

    Map<String, String> bowerDeps = {};

    Map<String, String> runInit = new Map();

    _libraryTree(r.getLibrary(t.primaryInput.id)).forEach((le) {
      AssetId libAsset = r.getSourceAssetId(le);
      if (libAsset == null) {
        t.logger.fine("SOURCE ASSET IS NULL FOR ${le} , ${le.source.uri}");
        return;
      }
      t.logger.fine("Examining ${libAsset}");
      Map<String, List<AnnotationInfo>> annotations =
          firstLevelAnnotationMap(le.units.map((e) => e.unit), {'bower': isBowerImport, 'html': isHtmlImport, 'js': isJsMap, 'initMod': isInitModule, 'reg': isPolymerRegister});

      String libKey = 'packages/${libAsset.package}/${p.split(p.withoutExtension(libAsset.path)).join('__')}';
      Set<String> libDeps = extraDeps.putIfAbsent(libKey, () => new Set());

      annotations['bower']?.forEach((o) {
        bowerDeps[o.annotation.getField('name').toStringValue()] = o.annotation.getField('ref').toStringValue();
        libDeps.add('polymerize_require/htmlimport!bower_components/${o.annotation.getField('import').toStringValue()}');
      });

      annotations['html']?.forEach((o) {
        libDeps.add(
            'polymerize_require/htmlimport!packages/${libAsset.package}/${p.relative(p.join(p.dirname(libAsset.path), o.annotation.getField('path').toStringValue()),from:'lib')}');
      });

      annotations['js']?.forEach((o) {
        libDeps.add(o.annotation.getField('mapped').toStringValue());
      });

      annotations['reg']?.forEach((o) {
        String template = o.annotation.getField('template').toStringValue();
        if (template == null) {
          return;
        }
        AssetId elemId = r.getSourceAssetId(o.element);
        String path = p.normalize(p.relative(p.join(p.dirname(elemId.path), template), from: 'lib'));
        libDeps.add('polymerize_require/htmlimport!packages/${elemId.package}/${path}');
      });

      if ((annotations['initMod'] ?? []).isNotEmpty) {
        if (annotations['initMod'].length > 1) {
          throw "There should be at least one `@initModule` annotation per library but '${le.source.uri}' has ${annotations['initMod'].length} !";
        }

        AnnotationInfo info = annotations['initMod'].single;
        runInit[libKey] = [p.split(p.withoutExtension(p.relative(libAsset.path, from: 'lib'))).join('__'), info.element.name].map((x) => "'${x}'").join(',');
      }
    });

    t.logger.fine("DEPS ARE :${bowerDeps}");
    if (bowerDeps.isNotEmpty) {
      AssetId bowerId = new AssetId(t.primaryInput.id.package, 'web/bower.json');
      Asset bowerJson = new Asset.fromString(bowerId, JSON.encode({'name': t.primaryInput.id.package, 'dependencies': bowerDeps}));
      t.addOutput(bowerJson);
    }

    // Write require config map
    if (extraDeps.isNotEmpty) {
      AssetId bowerId = new AssetId(t.primaryInput.id.package, 'web/require.map.js');
      AssetId polymer_loader = new AssetId(t.primaryInput.id.package, 'web/polymerize_require/loader.js');
      AssetId polymer_htmlimport = new AssetId(t.primaryInput.id.package, 'web/polymerize_require/htmlimport.js');
      t.addOutput(new Asset.fromString(polymer_loader, await t.readInputAsString(new AssetId('polymerize', 'lib/src/polymerize_require/loader.js'))));
      t.addOutput(new Asset.fromString(polymer_htmlimport, await t.readInputAsString(new AssetId('polymerize', 'lib/src/polymerize_require/htmlimport.js'))));
      t.addOutput(new Asset.fromString(
          new AssetId(t.primaryInput.id.package, 'web/polymerize_require/start.js'), await t.readInputAsString(new AssetId('polymerize', 'lib/src/polymerize_require/start.js'))));

      t.addOutput(new Asset.fromString(
          new AssetId(t.primaryInput.id.package, 'web/polymerize_require/require.js'), await t.readInputAsString(new AssetId('polymerize', 'lib/src/polymerize_require/require.js'))));
      Asset bowerJson = new Asset.fromStream(
          bowerId,
          () async* {
            yield "(function(){\n";
            yield " let polymerize_loader= {\n";

            for (String libKey in extraDeps.keys) {
              if (extraDeps[libKey].isEmpty) {
                continue;
              }
              yield "  '${libKey}' : [${extraDeps[libKey].map((x)=> "'${x}'").join(',')}],\n";
            }

            yield " };\n";
            yield " let polymerize_init = {\n";
            for (String libKey in runInit.keys) {
              yield "  '${libKey}' : [${runInit[libKey]}],\n";
            }
            yield " };\n";
            yield " polymerize_redefine(polymerize_loader,polymerize_init);\n";
            yield "})();\n";
          }()
              .transform(UTF8.encoder));
      t.addOutput(bowerJson);
    }
  }

  @override
  Future<bool> shouldApplyResolver(Asset asset) async {
    return asset.id.path.endsWith('.dart');
  }
}

class BowerInstallTransformer extends Transformer {
  BowerInstallTransformer.asPlugin(BarbackSettings settings);


  @override
  apply(Transform transform) async {

    // Run bower install in a temporary folder and make them run produce assets

    Directory dir  = await Directory.systemTemp.createTemp('bower_import');

    File bowerJson = new File(p.join(dir.path,'bower.json'));
    await bowerJson.writeAsString(await transform.primaryInput.readAsString());
    transform.logger.info("Downloading bower dependencies ...");
    ProcessResult res = await Process.run('bower', ['install'],workingDirectory: dir.path);
    if (res.exitCode!=0) {
      transform.logger.error("BOWER ERROR : ${res.stdout} / ${res.stderr}");
      throw "Error running bower install";
    }
    transform.logger.info("Downloading bower dependencies ... DONE");

    Directory bowerComponents = new Directory(p.join(dir.path,'bower_components'));

    await for (FileSystemEntity e in bowerComponents.list(recursive: true)) {
      if (e is File) {
        transform.addOutput(new Asset.fromFile(new AssetId(transform.primaryInput.id.package, "web/${p.relative(e.path,from:dir.path)}"),e));
      }
    }
  }

  @override
  isPrimary(AssetId id) => id.path=='web/bower.json';


}

Iterable<X> _dedupe<X>(Iterable<X> from) => new Set()..addAll(from);

bool _needsHtmlImport(LibraryElement importedLib) => hasAnyFirstLevelAnnotation(importedLib.units.map((u) => u.unit), anyOf([isInit, isPolymerRegister]));

String _packageUriToModuleName(Uri packageUri) => "packages/${packageUri.pathSegments[0]}/${p.withoutExtension(p.joinAll(packageUri.pathSegments.sublist(1)))}.mod.html";