import { Visitor } from '../javascript/estree-visitor';
import { JavaScriptDocument } from '../javascript/javascript-document';
import { JavaScriptScanner } from '../javascript/javascript-scanner';
import { ScannedElement, ScannedFeature } from '../model/model';
export interface ScannedAttribute extends ScannedFeature {
    name: string;
    type?: string;
}
export declare class Polymer2ElementScanner implements JavaScriptScanner {
    scan(document: JavaScriptDocument, visit: (visitor: Visitor) => Promise<void>): Promise<ScannedElement[]>;
}
