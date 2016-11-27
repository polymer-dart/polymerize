import { ScannedFeature } from '../model/model';
import { HtmlVisitor, ParsedHtmlDocument } from './html-document';
import { HtmlScanner } from './html-scanner';
export declare class HtmlScriptScanner implements HtmlScanner {
    scan(document: ParsedHtmlDocument, visit: (visitor: HtmlVisitor) => Promise<void>): Promise<ScannedFeature[]>;
}
