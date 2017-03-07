import { Visitor } from '../javascript/estree-visitor';
import { JavaScriptDocument } from '../javascript/javascript-document';
import { JavaScriptScanner } from '../javascript/javascript-scanner';
import { ScannedPolymerElementMixin } from './polymer-element-mixin';
export declare class Polymer2MixinScanner implements JavaScriptScanner {
    scan(document: JavaScriptDocument, visit: (visitor: Visitor) => Promise<void>): Promise<ScannedPolymerElementMixin[]>;
}
