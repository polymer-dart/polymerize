import { Visitor } from '../javascript/estree-visitor';
import { JavaScriptDocument } from '../javascript/javascript-document';
import { JavaScriptScanner } from '../javascript/javascript-scanner';
import { ScannedNamespace } from './namespace';
export declare class NamespaceScanner implements JavaScriptScanner {
    scan(document: JavaScriptDocument, visit: (visitor: Visitor) => Promise<void>): Promise<ScannedNamespace[]>;
}
