/**
 * @license
 * Copyright (c) 2017 The Polymer Project Authors. All rights reserved.
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
const chai_1 = require("chai");
const ts = require("typescript");
const analysis_context_1 = require("../../core/analysis-context");
const typescript_analyzer_1 = require("../../typescript/typescript-analyzer");
const package_url_resolver_1 = require("../../url-loader/package-url-resolver");
const test_utils_1 = require("../test-utils");
function getTypeScriptAnalyzer(files) {
    return __awaiter(this, void 0, void 0, function* () {
        const urlLoader = new test_utils_1.TestUrlLoader(files);
        const urlResolver = new package_url_resolver_1.PackageUrlResolver();
        const analysisContext = new analysis_context_1.AnalysisContext({ urlLoader, urlResolver });
        // This puts documents into the scanned document cache
        yield Promise.all(Object.keys(files).map((url) => analysisContext.scan(url)));
        return new typescript_analyzer_1.TypeScriptAnalyzer(analysisContext);
    });
}
suite('TypeScriptParser', () => {
    suite('parse()', () => {
        test('parses classes', () => __awaiter(this, void 0, void 0, function* () {
            const fileName = '/typescript/test.ts';
            const typescriptAnalyzer = yield getTypeScriptAnalyzer({
                [fileName]: `
          class A extends HTMLElement {
            foo() { return 'bar'; }
          }`
            });
            const program = typescriptAnalyzer.analyze(fileName);
            const checker = program.getTypeChecker();
            chai_1.assert.deepEqual(program.getRootFileNames(), [fileName]);
            // Get the HTMLElement type from the DOM module
            let htmlElement;
            const domSource = program.getSourceFile('/$lib/DOM.d.ts');
            ts.forEachChild(domSource, (node) => {
                if (node.kind === ts.SyntaxKind.InterfaceDeclaration) {
                    const innerface = node;
                    if (innerface.name.getText() === 'HTMLElement') {
                        htmlElement = checker.getTypeAtLocation(innerface);
                    }
                }
            });
            // Get class A and assert that it extends HTMLElement
            const sourceFile = program.getSourceFile(fileName);
            ts.forEachChild(sourceFile, (node) => {
                if (node.kind === ts.SyntaxKind.ClassDeclaration) {
                    const clazz = node;
                    if (clazz.name && clazz.name.getText() === 'A') {
                        const type = checker.getTypeAtLocation(clazz);
                        const baseTypes = checker.getBaseTypes(type);
                        chai_1.assert.include(baseTypes, htmlElement);
                        const properties = checker.getPropertiesOfType(type);
                        const ownProperties = properties.filter((p) => p.getDeclarations().some((d) => d.parent === clazz));
                        chai_1.assert.equal(ownProperties.length, 1);
                        chai_1.assert.equal(ownProperties[0].name, 'foo');
                    }
                }
            });
        }));
    });
});

//# sourceMappingURL=typescript-analyzer_test.js.map
