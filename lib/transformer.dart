import 'package:barback/barback.dart';
import 'package:polymerize/src/transformers.dart';

class PolymerizeTransformer extends TransformerGroup {
  PolymerizeTransformer.asPlugin(BarbackSettings settings) : super(_createPhases(settings)) {}

  static List<List> _createPhases(BarbackSettings settings) => [
        [new InoculateTransformer.asPlugin(settings)],
        [new GatheringTransformer.asPlugin(settings)],
        [new FinalizeTransformer.asPlugin(settings)],
        [new BowerInstallTransformer.asPlugin(settings)],
        [new TestTransfomer.asPlugin(settings)]
      ];
}
