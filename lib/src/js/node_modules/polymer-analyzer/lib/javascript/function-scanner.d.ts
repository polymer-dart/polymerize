import { Visitor } from '../javascript/estree-visitor';
import { JavaScriptDocument } from '../javascript/javascript-document';
import { JavaScriptScanner } from '../javascript/javascript-scanner';
import { ScannedFunction } from './function';
export declare class FunctionScanner implements JavaScriptScanner {
    scan(document: JavaScriptDocument, visit: (visitor: Visitor) => Promise<void>): Promise<ScannedFunction[]>;
}
