import { Visitor } from '../javascript/estree-visitor';
import { JavaScriptDocument } from '../javascript/javascript-document';
import { ScannedPolymerCoreFeature } from './polymer-core-feature';
export declare function featureScanner(document: JavaScriptDocument): {
    visitors: Visitor;
    features: ScannedPolymerCoreFeature[];
};
