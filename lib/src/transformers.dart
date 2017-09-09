import 'dart:async';
import 'dart:convert';

import 'dart:core';
import 'dart:io';
import 'package:analyzer/analyzer.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:barback/barback.dart';
import 'package:build/src/builder/builder.dart';
import 'package:code_transformers/resolver.dart';
import 'package:glob/glob.dart';
import 'package:polymerize/src/code_generator.dart';
import 'package:polymerize/src/dart_file_command.dart';
import 'package:polymerize/src/dep_analyzer.dart';
import 'package:code_builder/code_builder.dart';
import 'package:resource/resource.dart';

import 'package:path/path.dart' as p;
import 'package:polymerize/src/utils.dart';
import 'package:package_config/packages.dart';
import 'package:build_barback/build_barback.dart';
import 'package:source_gen/source_gen.dart' as source_gen;


import 'dart:io';

class ResolversInternalContext implements InternalContext {
  Resolver _resolver;
  String packageName;
  String prefix;

  AssetId toAssetId(String uriString) {
    Uri uri = Uri.parse(uriString);
    if (uri.scheme == 'package') {
      AssetId assetId = new AssetId(uri.pathSegments[0], "lib/${uri.pathSegments.sublist(1).join("/")}");
      return assetId;
    } else {
      return new AssetId(packageName, "${prefix}/${uriString}");
    }
    throw "Unknown URI ${uriString}";
  }

  ResolversInternalContext(Resolver resolver, this.packageName, this.prefix) : _resolver = resolver;

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

Iterable<LibraryElement> _referencedLibs(LibraryElement lib) sync* {
  yield* lib.imports.map((i) => i.importedLibrary);
  yield* lib.exports.map((e) => e.exportedLibrary);
}

const String EXT = '.polymerize.dart';

class PartGeneratorTransformer extends BuilderTransformer {
  PartGeneratorTransformer() : super(polymerizePartBuilder());

}

Builder polymerizePartBuilder({String extension:EXT}) => new source_gen.LibraryBuilder(new PolymerizeDartGenerator(),generatedExtension: extension,formatOutput: (str) => str);

class InoculateTransformer extends Transformer with ResolverTransformer {
  InoculateTransformer({bool releaseMode, this.settings}) {
    resolvers = new Resolvers(dartSdkDirectory);
  }
  BarbackSettings settings;

  InoculateTransformer.asPlugin(BarbackSettings settings) : this(releaseMode: settings.mode == BarbackMode.RELEASE, settings: settings);

  Future<bool> isPrimary(id) async {
    return id.path.endsWith(ORIG_EXT) /* && id.path.startsWith("lib/")*/;
  }

  AssetId toDest(AssetId orig) => new AssetId(orig.package, orig.path.substring(0, orig.path.length - ORIG_EXT.length) + EXT);

  @override
  applyResolver(Transform transform, Resolver resolver) async {
    if (!resolver.isLibrary(transform.primaryInput.id) || !needsProcessing(resolver.getLibrary(transform.primaryInput.id))) {
      transform.logger.fine("${transform.primaryInput.id} is NOT a library, skipping");
      return;
    }
    transform.logger.fine("POLYMERIZE VERSION:DEV");
    transform.logger.fine("Processing ${transform.primaryInput.id}");
    AssetId origId = transform.primaryInput.id;
    AssetId dest = toDest(origId);

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
    return asset.id.path.endsWith('.dart')&&!asset.id.path.endsWith(EXT);
  }
}

/**
 * Examines all the entry points
 */
class GatheringTransformer extends Transformer with ResolverTransformer {
  static const String EXTENSION = '.polymerize_summary';

  GatheringTransformer({bool releaseMode, this.settings}) {
    resolvers = new Resolvers(dartSdkDirectory);
  }
  BarbackSettings settings;

  GatheringTransformer.asPlugin(BarbackSettings settings) : this(releaseMode: settings.mode == BarbackMode.RELEASE, settings: settings);

  static List<X> asList<X>(something) {
    if (something == null) {
      return [];
    } else if (something is List) {
      return something;
    } else if (something is Iterable) {
      return new List.from(something);
    } else {
      return [something];
    }
  }

  Future<bool> isPrimary(id) async {
    Iterable<Glob> entryPoints = asList(settings.configuration['entry-point'] ?? settings.configuration['entry-points']).map((x) => new Glob(x));
    return entryPoints.any((g) => g.matches(id.path));
  }

  @override
  applyResolver(Transform transform, Resolver resolver) async {
    // generate bower.json
    if (!settings.configuration.containsKey('entry-point') && !settings.configuration.containsKey('entry-points')) {
      return;
    }

    transform.logger.fine("GENERATING BOWER.JSON WITH ${settings.configuration}", asset: transform.primaryInput.id);

    await _generateBowerJson(transform, resolver);
  }

  Future _generateBowerJson(Transform t, Resolver r) async {
    // Check if current lib matches

    if (!r.isLibrary(t.primaryInput.id)) {
      return;
    }
    t.logger.fine("PRODUCING POLYMERIZE SUMMARY FOR ${t.primaryInput.id}");

    // Create bower.json and collect all extra deps

    Map<String, Set<String>> extraDeps = {};

    Map<String, String> bowerDeps = {};

    Map<String, String> runInit = new Map();

    Set<String> basePaths = new Set();

    _libraryTree(r.getLibrary(t.primaryInput.id)).forEach((le) {
      AssetId libAsset = r.getSourceAssetId(le);
      if (libAsset == null) {
        t.logger.fine("SOURCE ASSET IS NULL FOR ${le} , ${le.source.uri}");
        return;
      }
      t.logger.fine("Examining ${libAsset}");

      // Collect web / test base paths
      basePaths.add(p.split(libAsset.path).first);

      Map<String, List<AnnotationInfo>> annotations = firstLevelAnnotationMap(
          le.units.map((e) => e.unit), {'bower': isBowerImport, 'html': isHtmlImport, 'js': isJsMap, 'initMod': isInitModule, 'reg': isPolymerRegister}, 'other');

      String libKey = toModuleJs(libAsset);

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

      if (annotations['initMod']?.isNotEmpty ?? false) {
        if (annotations['initMod'].length > 1) {
          throw "There should be at least one `@initModule` annotation per library but '${le.source.uri}' has ${annotations['initMod'].length} !";
        }

        AnnotationInfo info = annotations['initMod'].single;
        runInit[libKey] = [p.split(p.withoutExtension(libAsset.path)).sublist(1).join('__'), info.element.name].map((x) => "'${x}'").join(',');
      }
    });

    // Produces an asset

    AssetId resultId = t.primaryInput.id.changeExtension(EXTENSION);
    Asset result = new Asset.fromString(
        resultId,
        JSON.encode({
          'basePaths': new List.from(basePaths),
          'extraDeps': new Map.fromIterable(extraDeps.keys, value: (k) => new List.from(extraDeps[k])),
          'bowerDeps': bowerDeps,
          'runInit': runInit
        }));
    t.addOutput(result);
  }

  String toModuleJs(AssetId libAsset) {
    String libKey;
    if (libAsset.path.startsWith('lib')) {
      libKey = 'packages/${libAsset.package}/${p.split(p.withoutExtension(libAsset.path)).join('__')}';
    } else if (libAsset.path.startsWith('web')) {
      libKey = '${p.split(p.withoutExtension(libAsset.path)).join('__')}';
    } else if (libAsset.path.startsWith('test')) {
      libKey = 'test/${p.split(p.withoutExtension(libAsset.path)).join('__')}';
    }
    return libKey;
  }

  @override
  Future<bool> shouldApplyResolver(Asset asset) async {
    return asset.id.path.endsWith('.dart');
  }
}

class FinalizeTransformer extends AggregateTransformer {
  FinalizeTransformer({bool releaseMode, this.settings}) {}
  BarbackSettings settings;

  FinalizeTransformer.asPlugin(BarbackSettings settings) : this(releaseMode: settings.mode == BarbackMode.RELEASE, settings: settings);

  @override
  apply(AggregateTransform transform) async {
    await _generateBowerJson(transform);
  }

  Future _generateBowerJson(AggregateTransform t) async {
    // Check if current lib matches

    t.logger.fine("PRODUCING BOWER.JSON FOR ${t.package} [${t.key}]");

    // Create bower.json and collect all extra deps

    Map<String, Set<String>> extraDeps = {};

    Map<String, String> bowerDeps = {};

    Map<String, String> runInit = new Map();

    Set<String> basePaths = new Set();

    await for (Asset asset in t.primaryInputs) {
      t.logger.fine('Merging metadata from ${asset.id}');
      // Merge
      Map current = JSON.decode(await asset.readAsString());
      Map<String, List<String>> _extraDeps = current['extraDeps'];
      if (_extraDeps != null) {
        _extraDeps.forEach((k, vals) {
          Set<String> _deps = extraDeps.putIfAbsent(k, () => new Set<String>());
          _deps.addAll(vals);
        });

        Map<String, String> _bowerDeps = current['bowerDeps'] ?? {};
        t.logger.fine("Deps :${_bowerDeps}", asset: asset.id);
        bowerDeps.addAll(_bowerDeps);

        Map<String, String> _runInit = current['runInit'] ?? {};
        t.logger.fine("Init :${_runInit}", asset: asset.id);
        runInit.addAll(_runInit);

        List<String> _basePaths = current['basePaths'] ?? [];
        t.logger.fine("Base :${_basePaths}");
        basePaths.addAll(_basePaths);
      }

      // Consuming
      t.logger.fine('Consumed ${asset.id}');
      t.consumePrimary(asset.id);
    }

    t.logger.fine("FINAL DEPS ARE :${bowerDeps}");
    t.logger.fine("FINAL extraDeps ARE :${extraDeps}");
    t.logger.fine("FINAL runInit ARE :${runInit}");
    t.logger.fine("BASE PATHS : ${basePaths}");

    await Future.wait(basePaths.where((String p) => p != 'lib').map((String basePath) async {
      t.logger.fine('Producing things for ${basePath}');
      if (bowerDeps.isNotEmpty) {
        Map conf = new Map()..addAll(settings.configuration['bower'] ?? {});
        conf
          ..['name'] = t.package
          ..['dependencies'] = (conf['dependencies'] ?? {}
            ..addAll(bowerDeps));

        AssetId bowerId = new AssetId(t.package, '${basePath}/bower.json');
        Asset bowerJson = new Asset.fromString(bowerId, JSON.encode(conf));
        t.addOutput(bowerJson);
      }

      // Write require config map
      if (extraDeps.isNotEmpty || runInit.isNotEmpty) {
        AssetId bowerId = new AssetId(t.package, '${basePath}/require.map.js');
        AssetId dart_test = new AssetId(t.package, '${basePath}/polymerize_require/dart_test.js');
        AssetId polymer_htmlimport = new AssetId(t.package, '${basePath}/polymerize_require/htmlimport.js');
        t.addOutput(new Asset.fromString(dart_test, await t.readInputAsString(new AssetId('polymerize', 'lib/src/polymerize_require/dart_test.js'))));
        t.addOutput(new Asset.fromString(polymer_htmlimport, await t.readInputAsString(new AssetId('polymerize', 'lib/src/polymerize_require/htmlimport.js'))));
        t.addOutput(new Asset.fromString(
            new AssetId(t.package, '${basePath}/polymerize_require/start.js'),
            await t.readInputAsString(
                new AssetId('polymerize', settings.mode == BarbackMode.DEBUG ? 'lib/src/polymerize_require/start_debug.js' : 'lib/src/polymerize_require/start.js'))));

        t.addOutput(new Asset.fromString(
            new AssetId(t.package, '${basePath}/polymerize_require/require.js'), await t.readInputAsString(new AssetId('polymerize', 'lib/src/polymerize_require/require.js'))));
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
              yield "define('_start',['dart_sdk'],function(dart_sdk) {\n";
              yield "  patch_dart_sdk(dart_sdk);\n"; // PATCH&OPTIMIZE THE DART SDK
              yield "  return () => { dart_sdk._isolate_helper.startRootIsolate(() => {}, []); dart_sdk._isolate_helper.startRootIsolate = function(){}; }\n";
              yield "});\n";
              yield "require(['_start'],function(s) { s(); });\n";
              yield " polymerize_redefine(polymerize_loader,polymerize_init);\n";
              yield "})();\n";
            }()
                .transform(UTF8.encoder));
        t.addOutput(bowerJson);
      }
    }));
  }

  @override
  classifyPrimary(AssetId id) => id.path.endsWith(GatheringTransformer.EXTENSION) ? 'polymerize_summary' : null;
}

class BowerInstallTransformer extends Transformer {
  BarbackSettings settings;
  BowerInstallTransformer.asPlugin(this.settings);

  @override
  apply(Transform transform) async {
    // Run bower install in a temporary folder and make them run produce assets

    String basePath = p.split(transform.primaryInput.id.path).first;

    Directory dir = await Directory.systemTemp.createTemp('bower_import');
    String bowerCmd = Platform.isWindows ? 'bower.cmd' : 'bower';

    try {
      ProcessResult res = await Process.run(bowerCmd, ['-v'], workingDirectory: dir.path);
      if (res.exitCode != 0) {
        throw "Bower execution failed : ${res.stderr} , ${res.stdout}";
      }
    } catch (error) {
      transform.logger.warning('Could not find bower, skipping bower install phase: ${error}');
      return;
    }

    transform.logger.fine('Using temp dir ${dir.path}');
    File bowerJson = new File(p.join(dir.path, 'bower.json'));

    await bowerJson.writeAsString(await transform.primaryInput.readAsString());
    transform.logger.fine('Created ${bowerJson.path}');
    transform.logger.info("Downloading bower dependencies ...");

    ProcessResult res = await Process.run(bowerCmd, ['install'], workingDirectory: dir.path);
    if (res.exitCode != 0) {
      transform.logger.error("BOWER ERROR : ${res.stdout} / ${res.stderr}");
      transform.logger.error("BOWER:\n${await bowerJson.readAsString()}");
      throw "Error running bower install";
    }
    transform.logger.info("Downloading bower dependencies ... DONE");

    Directory bowerComponents = new Directory(p.join(dir.path, 'bower_components'));

    await for (FileSystemEntity e in bowerComponents.list(recursive: true)) {
      if (e is File) {
        transform.addOutput(new Asset.fromFile(new AssetId(transform.primaryInput.id.package, "${basePath}/${p.relative(e.path,from:dir.path)}"), e));
      }
    }
  }

  @override
  isPrimary(AssetId id) => id.path.endsWith('/bower.json');
}

class TestTransfomer extends Transformer with ResolverTransformer {
  @override
  Future<bool> isPrimary(AssetId id) async => id.path.startsWith('test/') && id.path.endsWith('.dart');

  BarbackSettings settings;

  TestTransfomer.asPlugin(this.settings) {
    resolvers = new Resolvers(dartSdkDirectory);
  }

  @override
  Future<bool> shouldApplyResolver(Asset asset) async => asset.id.path.endsWith('.dart');

  @override
  applyResolver(Transform transform, Resolver resolver) async {
    if (!resolver.isLibrary(transform.primaryInput.id)) {
      return;
    }

    LibraryElement origLib = resolver.getLibrary(transform.primaryInput.id);
    FunctionElement mainFunction = origLib.definingCompilationUnit.functions.firstWhere((fe) => fe.name == 'main', orElse: () => null);
    if (mainFunction == null) {
      return;
    }

    AssetId newLibId = transform.primaryInput.id.addExtension('.browser_test.dart');

    // Generate the output
    Scope scope = new Scope.dedupe();

    LibraryBuilder libraryBuilder = new LibraryBuilder.scope(scope: scope);
    libraryBuilder.addDirective(new ImportBuilder(resolver.getImportUri(origLib, from: newLibId).toString(), prefix: 'orig'));
    MethodBuilder mainBuilder = new MethodBuilder.returnVoid('main')
      ..addStatements(() sync* {
        ExpressionBuilder origMain = reference('orig.main');
        ExpressionBuilder runTest = reference('runTest','package:polymerize/test_support.dart');
        yield runTest.call([origMain]);
      }());
    libraryBuilder.addMember(mainBuilder);

    transform.addOutput(new Asset.fromString(newLibId, prettyToSource(libraryBuilder.buildAst(scope))));

    // If the user has their own HTML file for the test, let that take
    // precedence. Otherwise, create our own basic file.
    var htmlId = transform.primaryInput.id.changeExtension('.html');
    if (await transform.hasInput(htmlId)) return;

    transform.addOutput(new Asset.fromString(
        htmlId,
        '''
          <!DOCTYPE html>
          <html>
          <head>
            <title>${HTML_ESCAPE.convert(transform.primaryInput.id.path)} Test</title>
            <link rel="x-dart-test"
                  href="${HTML_ESCAPE.convert(p.url.basename(transform.primaryInput.id.path))}">
            <script src="polymerize_require/dart_test.js"></script>
            <!-- needed because pub will refuse executing otherwise
              <script src="packages/test/dart.js"></script>
            -->

          </head>
          </html>
        '''));
  }
}

Iterable<X> _dedupe<X>(Iterable<X> from) => new Set()..addAll(from);

bool _needsHtmlImport(LibraryElement importedLib) => hasAnyFirstLevelAnnotation(importedLib.units.map((u) => u.unit), anyOf([isInit, isPolymerRegister]));

String _packageUriToModuleName(Uri packageUri) => "packages/${packageUri.pathSegments[0]}/${p.withoutExtension(p.joinAll(packageUri.pathSegments.sublist(1)))}.mod.html";
