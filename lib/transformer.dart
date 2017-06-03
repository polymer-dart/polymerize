import 'package:barback/barback.dart';
import 'package:polymerize/src/transformer.dart';

class PolymerizeTransformer extends TransformerGroup {
  PolymerizeTransformer.asPlugin(BarbackSettings settings) : super(_createPhases(settings)) {}

  static List<List> _createPhases(BarbackSettings settings) => [
        [new PrepareTransformer.asPlugin(settings)],
        [new InoculateTransformer.asPlugin(settings)]
      ];
}
