import 'dart:async';
import 'dart:io';

import 'package:analyzer/analyzer.dart' as analyzer;
import 'package:analyzer/dart/element/element.dart' as dart;
import 'package:analyzer/dart/element/visitor.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/src/dart/sdk/sdk.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/source.dart';
import 'package:build/build.dart' as buildy;
import 'package:front_end/src/base/source.dart';
import 'package:glob/glob.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'package:polymerize/src/utils.dart';
import 'package:path/path.dart' as path;

class CheckEntrypointVisitor extends GeneralizingElementVisitor<bool> {
  bool found = false;

  CheckEntrypointVisitor(dart.LibraryElement le) {
    le.accept(this);
  }

  @override
  bool visitElement(dart.Element element) {
    if (getAnnotation(element.metadata, isEntryPoint) != null) {
      found = true;
      return true;
    }
    return super.visitElement(element);
  }
}

class HtmlWrapperBuilder extends buildy.Builder {
  Glob entryPoints;

  HtmlWrapperBuilder({this.entryPoints});

  @override
  Future build(buildy.BuildStep buildStep) async {
    Document doc = parse(await buildStep.readAsString(buildStep.inputId));

    // lookup for the main entry point
    Element e = doc.querySelector('script[type="application/dart"]');
    if (e == null) {
      return;
    }

    buildy.AssetId destId = buildStep.inputId.changeExtension('.webpack.html');

    Iterable<buildy.AssetId> dartEntryPoints =
        buildStep.findAssets(entryPoints);
    MyAnalyzer res =
        /*await buildStep.fetchResource(
        new buildy.Resource<MyAnalyzer>(
            () => MyAnalyzer.create(buildStep, dartEntryPoints),
            dispose: (res) => res.release()));
*/
        await MyAnalyzer.create(buildStep, dartEntryPoints);

    //print('READ ALL ASSETS, NOW ANALYZE ONE BY ONE');

    // lookup for any possible entrypoint
    Iterable<dart.LibraryElement> libs = dartEntryPoints
        .map((assetId) {
          print('looking up entry-point ${assetId}');
          if (res.isLibrary(assetId)) {
            return res.getLibrary(assetId);
          }

          print("skipping ${assetId} : it's not a lib!");
          return null;
        })
        .where((le) => le != null)
        .toList();

    //print('found ${libs.length} elements');

    // Now gather every imports

    Set<String> visits = new Set();
    Stream<DocumentFragment> imports = _crawlImportsForLibs(res, libs, visits);

    Element div = doc.createElement('div');
    doc.body.insertBefore(div, doc.body.firstChild);
    div.attributes['style'] = 'display:none;';

    await for (DocumentFragment fragment in imports) {
      div.append(fragment.clone(true));
    }

    // Get Library Element MAIN ENTRY POINT

    String mainEntryPointName = path.basenameWithoutExtension(e.attributes['src']);
    //dart.LibraryElement mainEntryPoint = res.getLibrary(new buildy.AssetId.resolve(mainEntryPointName));

    //

    // finally adds `common.js` script and bootloader

    div.append(doc.createElement('div')
      ..innerHtml = '''
<script src="common.js"></script>
<!--
    <script src="index.js"></script>
-->
<script>


  // TODO : MOVE THIS INTO WEBPACK
  
    
  require(['patched_sdk','web__${mainEntryPointName}'], function(sdk,mainModule) {
      mainModule.${mainEntryPointName}.main();
  });

</script>
''');

    // Finally remove polymerize script
    Element polyScript = doc.querySelector('script[src="polymerize_require/start.js"]');
    if (polyScript!=null) {
      polyScript.attributes['src']= 'require.js';
    }
    e.remove(); // remove dart script too

    await buildStep.writeAsString(destId, doc.outerHtml);
  }

  Stream<DocumentFragment> _crawlImportsForLibs(MyAnalyzer analyzer,
      Iterable<dart.LibraryElement> les, Set<String> visits) async* {
    for (dart.LibraryElement le
        in les.where((l) => !visits.contains(l.source.uri.toString()))) {
      yield* _crawlImportsForLib(analyzer, le, visits);
    }
  }

  Stream<DocumentFragment> _crawlImportsForLib(
      MyAnalyzer analyzer, dart.LibraryElement le, Set<String> visits) async* {
    // First check here for every import
    visits.add(le.source.uri.toString());
    /*le.unit.directives.where((d)=>d is analyzer.ImportDirective).map((i)=>(i as analyzer.ImportDirective).uri.stringValue).where((u)=>u!=null&&!u.startsWith('dart:'))
      .map((s)=>le.context.res)
    le = le.context.computeLibraryElement(le.source);
*/
    //print("Look for imports in ${le.source.uri} (with ${le.imports.length}) imports : ${le.imports}");

    // Recurr first on libs
    yield* _crawlImportsForLibs(analyzer,
        le.importedLibraries.where((l) => !(l?.isInSdk ?? true)), visits);

    Map<String, List<AnnotationInfo>> map = firstLevelAnnotationMap(
        le.units.map((u) => u.computeNode()),
        {'htmlImport': isHtmlImport, 'bowerImport': isBowerImport,'polymer':isPolymerRegister},
        'other');

    for (AnnotationInfo info in map['htmlImport'] ?? []) {
      // Parse the doc
      String path = info.annotation.getField('path').toStringValue();
      Uri assetUri = le.source.uri.resolve(path);

      yield* _crawlUri(analyzer, assetUri, visits);
    }

    for (AnnotationInfo info in map['bowerImport'] ?? []) {
      // TODO : bower download somewhere to get this (should make an uri resolver ?)
      String import = info.annotation.getField('import').toStringValue();
      Uri assetUri = Uri.parse('bower:/${import}');
      // Parse the doc
      yield* _crawlUri(analyzer, assetUri, visits);
    }

    for (AnnotationInfo info in map['polymer'] ?? []) {
      // TODO : bower download somewhere to get this (should make an uri resolver ?)
      String templ = info.annotation.getField('template')?.toStringValue();
      if (templ==null) {
        continue;
      }
      Uri assetUri = le.source.uri.resolve(templ);

      yield* _crawlUri(analyzer, assetUri, visits);
    }
  }

  Stream<DocumentFragment> _crawlUri(
      MyAnalyzer analyzer, Uri uri, Set<String> visits) async* {
    if (visits.contains(uri.toString())) {
      return;
    }
    visits.add(uri.toString());
    DocumentFragment document;
    Uri pubUri;
    if (uri.scheme == 'bower') {
      String p = "bower_components${uri.path}";
      pubUri=Uri.parse(p);
      document = parseFragment(
          new File('build/web/${p}').readAsStringSync());
    } else {

      pubUri=Uri.parse('packages/${uri.pathSegments[0]}/${uri.pathSegments.sublist(2).join('/')}');
      document = parseFragment(await analyzer.buildStep.readAsString(
          new buildy.AssetId(
              uri.pathSegments[0], uri.pathSegments.sublist(1).join('/'))));
    }

    // Process each link and replace with the doc
    List<Element> links = document.querySelectorAll('link[rel="import"]');
    for (Element e in links) {
      Uri linkUri = uri.resolve(e.attributes['href']);
      print("Resolver ${linkUri} from ${uri} and ${e.attributes['href']}");
      yield* _crawlUri(analyzer, linkUri, visits);
    }

    new List.from(links).forEach((e) => e.remove());


    // Adjust references

    [
      'action',
      '_action', // in form
      'background',
      '_background', // in body
      'cite',
      '_cite', // in blockquote, del, ins, q
      'data',
      '_data', // in object
      'formaction',
      '_formaction', // in button, input
      'href',
      '_href', // in a, area, link, base, command
      'icon',
      '_icon', // in command
      'manifest',
      '_manifest', // in html
      'poster',
      '_poster', // in video
      'src',
      '_src', // in audio, embed, iframe, img, input, script, source, track,video
    ].forEach((attribute) {
      document.querySelectorAll('[${attribute}]').forEach((e) {
        if (isCustomTagName(e.localName))
          return;
        // Fix attribute
        e.attributes[attribute]=pubUri.resolve(e.attributes[attribute]).toString();
      });
    });

    // now release the doc
    yield document;
  }

  // TODO: implement buildExtensions
  @override
  Map<String, List<String>> get buildExtensions => {
        '.html': ['.webpack.html']
      };
}

bool isCustomTagName(String name) {
  if (name == null || !name.contains('-')) return false;
  return !invalidTagNames.containsKey(name);
}

/// These names have meaning in SVG or MathML, so they aren't allowed as custom
/// tags. See [isCustomTagName].
const invalidTagNames = const {
  'annotation-xml': '',
  'color-profile': '',
  'font-face': '',
  'font-face-src': '',
  'font-face-uri': '',
  'font-face-format': '',
  'font-face-name': '',
  'missing-glyph': '',
};

Uri _toUri(buildy.AssetId assetId) =>
    Uri.parse('asset:${assetId.package}/${assetId.path}');

class MyAnalyzer {
  Map<buildy.AssetId, BuildStepSource> _sources;
  buildy.BuildStep buildStep;

  AnalysisContext _context;

  MyAnalyzer._(this.buildStep);

  static Future<MyAnalyzer> create(
      buildy.BuildStep buildStep, List<buildy.AssetId> entryPoints) async {
    MyAnalyzer analyzer = new MyAnalyzer._(buildStep);
    await analyzer.init(entryPoints);
    return analyzer;
  }

  Future init(List<buildy.AssetId> entryPoints) async {
    AnalysisEngine engine = AnalysisEngine.instance;
    _sources = {};
    Map<buildy.AssetId, Future<BuildStepSource>> visits = {};
    await Future.forEach(entryPoints, (r) => _readEntryPoint(r, visits));

    PhysicalResourceProvider resourceProvider =
        PhysicalResourceProvider.INSTANCE;

    FolderBasedDartSdk sdk = new FolderBasedDartSdk(resourceProvider,
        FolderBasedDartSdk.defaultSdkDirectory(resourceProvider));

    UriResolver provider = new BuildStepUriResolver(
        new Map.fromIterable(_sources.values, key: (s) => s.uri.toString()));
    SourceFactory sourceFactory =
        new SourceFactory([new DartUriResolver(sdk), provider]);

    _context = engine.createAnalysisContext()
      ..sourceFactory = sourceFactory
      ..analysisOptions = (new AnalysisOptionsImpl()
        ..strongMode = true
        ..analyzeFunctionBodies = false);
  }

  Future<BuildStepSource> _readEntryPoint(buildy.AssetId assetId,
      Map<buildy.AssetId, Future<BuildStepSource>> visits) {
    return visits.putIfAbsent(assetId, () async {
      String content = await buildStep.readAsString(assetId);
      // Add source
      _sources[assetId] = new BuildStepSource(assetId, content);

      // recurr on imports
      analyzer.CompilationUnit cu = analyzer.parseCompilationUnit(content,
          name: assetId.toString(), parseFunctionBodies: false);
      await Future.forEach(
          cu.directives
              .where((e) =>
                  e is analyzer.ImportDirective &&
                  !e.uri.stringValue.startsWith('dart:'))
              .map((dir) => _resolveAsset(
                  assetId, (dir as analyzer.ImportDirective).uri.stringValue))
              .where((id) => !visits.containsKey(id)), (buildy.AssetId id) {
        return _readEntryPoint(id, visits);
      });

      return _sources[assetId];
    });
  }

  buildy.AssetId _resolveAsset(buildy.AssetId from, String uri) =>
      uri.startsWith('dart:')
          ? null
          : new buildy.AssetId.resolve(uri, from: from);

  dart.LibraryElement getLibrary(buildy.AssetId assetId) {
    Source source = _context.sourceFactory.forUri2(_toUri(assetId));
    return _context.computeLibraryElement(source);
  }

  bool isLibrary(buildy.AssetId assetId) {
    return _context.computeLibraryElement(
            _context.sourceFactory.forUri2(_toUri(assetId))) !=
        null;
  }

  void release() {}
}

class BuildStepUriResolver implements UriResolver {
  Map<String, BuildStepSource> sources;

  BuildStepUriResolver(this.sources);

  @override
  Source resolveAbsolute(Uri uri, [Uri actualUri]) {
    Uri u = actualUri ?? uri;
    if (u.scheme == 'package') {
      u = Uri.parse(
          'asset:${u.pathSegments[0]}/lib/${u.pathSegments.sublist(1).join('/')}');
    }
    return sources[u.toString()];
  }

  @override
  Uri restoreAbsolute(Source source) {
    if (source is BuildStepSource) {
      return source.uri;
    }

    return null;
  }
}

class BuildStepSource extends BasicSource {
  buildy.AssetId assetId;
  String stringContent;
  DateTime contentStamp;

  BuildStepSource(this.assetId, this.stringContent, [this.contentStamp])
      : super(_toUri(assetId)) {
    if (contentStamp == null) {
      contentStamp = new DateTime.now();
    }
  }

  @override
  TimestampedData<String> get contents =>
      new TimestampedData(contentStamp.millisecondsSinceEpoch, stringContent);

  @override
  bool exists() => stringContent != null;

  @override
  int get modificationStamp => contentStamp.millisecondsSinceEpoch;

  @override
  UriKind get uriKind => UriKind.PACKAGE_URI;
}
