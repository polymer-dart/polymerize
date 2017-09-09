import 'package:barback/barback.dart';
import 'package:polymerize/src/transformers.dart';

class PolymerizeTransformer extends TransformerGroup {
  PolymerizeTransformer.asPlugin(BarbackSettings settings)
      : super(_createPhases(settings)) {
  }

  static List<List> _createPhases(BarbackSettings settings) {
    List<List> res;

    if (settings.configuration.containsKey("skip-generate")) {
      res = [];
    } else {
      res = [
        [new InoculateTransformer.asPlugin(settings)],
        [new PartGeneratorTransformer()],
      ];
    }

    res.addAll([
      [new GatheringTransformer.asPlugin(settings)],
      [new FinalizeTransformer.asPlugin(settings)],
      [new BowerInstallTransformer.asPlugin(settings)],
      [new TestTransfomer.asPlugin(settings)],
    ]);

    return res;
  }
}
