import { Visitor } from '../javascript/estree-visitor';
import { JavaScriptDocument } from '../javascript/javascript-document';
import { JavaScriptScanner } from '../javascript/javascript-scanner';
import { ScannedImport } from '../model/model';
export declare class JavaScriptImportScanner implements JavaScriptScanner {
    scan(document: JavaScriptDocument, visit: (visitor: Visitor) => Promise<void>): Promise<ScannedImport[]>;
}
