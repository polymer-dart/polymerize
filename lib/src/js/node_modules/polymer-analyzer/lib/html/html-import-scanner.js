/**
 * @license
 * Copyright (c) 2016 The Polymer Project Authors. All rights reserved.
 * This code may only be used under the BSD style license found at
 * http://polymer.github.io/LICENSE.txt
 * The complete set of authors may be found at
 * http://polymer.github.io/AUTHORS.txt
 * The complete set of contributors may be found at
 * http://polymer.github.io/CONTRIBUTORS.txt
 * Code distributed by Google as part of the polymer project is also
 * subject to an additional IP rights grant found at
 * http://polymer.github.io/PATENTS.txt
 */
"use strict";
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : new P(function (resolve) { resolve(result.value); }).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
Object.defineProperty(exports, "__esModule", { value: true });
const dom5 = require("dom5");
const url_1 = require("url");
const model_1 = require("../model/model");
const p = dom5.predicates;
const linkTag = p.hasTagName('link');
const notCssLink = p.NOT(p.hasAttrValue('type', 'css'));
const isHtmlImportNode = p.AND(linkTag, p.hasAttr('href'), p.hasSpaceSeparatedAttrValue('rel', 'import'), p.NOT(p.hasSpaceSeparatedAttrValue('rel', 'lazy-import')), notCssLink, p.NOT(p.parentMatches(p.hasTagName('template'))));
const isLazyImportNode = p.AND(p.hasTagName('link'), p.hasSpaceSeparatedAttrValue('rel', 'lazy-import'), p.hasAttr('href'), p.NOT(p.hasSpaceSeparatedAttrValue('rel', 'import')), notCssLink, p.parentMatches(p.AND(p.hasTagName('dom-module'), p.NOT(p.hasTagName('template')))));
/**
 * Scans for <link rel="import"> and <link rel="lazy-import">
 */
class HtmlImportScanner {
    constructor(_lazyEdges) {
        this._lazyEdges = _lazyEdges;
    }
    scan(document, visit) {
        return __awaiter(this, void 0, void 0, function* () {
            const imports = [];
            yield visit((node) => {
                let type;
                if (isHtmlImportNode(node)) {
                    type = 'html-import';
                }
                else if (isLazyImportNode(node)) {
                    type = 'lazy-html-import';
                }
                else {
                    return;
                }
                const href = dom5.getAttribute(node, 'href');
                const importUrl = url_1.resolve(document.baseUrl, href);
                imports.push(new model_1.ScannedImport(type, importUrl, document.sourceRangeForNode(node), document.sourceRangeForAttributeValue(node, 'href'), node));
            });
            if (this._lazyEdges) {
                const edges = this._lazyEdges.get(document.url);
                if (edges) {
                    for (const edge of edges) {
                        imports.push(new model_1.ScannedImport('lazy-html-import', edge, undefined, undefined, null));
                    }
                }
            }
            return imports;
        });
    }
}
exports.HtmlImportScanner = HtmlImportScanner;

//# sourceMappingURL=html-import-scanner.js.map
