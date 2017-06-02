
import 'dart:async';
import 'dart:convert';
import 'package:barback/barback.dart';

class InitTransformer extends AggregateTransformer {

  InitTransformer.asPlugin(BarbackSettings settings);

  @override
  apply(AggregateTransform transform) {
    AssetId id = new AssetId(transform.package, "lib/assets.list");
    Asset res= new Asset.fromStream(id, _generateAssetList(transform).transform(UTF8.encoder));
    transform.addOutput(res);
  }

  Stream<String> _generateAssetList(AggregateTransform transform) async* {
    yield "Assets for ${transform.key} , ${transform.package}:";
    await for (Asset asset in  transform.primaryInputs) {
      yield "${asset.id}";
    }
  }

  @override
  classifyPrimary(AssetId id) {
    if (id.extension=='.dart') {
      return "DART";
    }
    return null;
  }
}