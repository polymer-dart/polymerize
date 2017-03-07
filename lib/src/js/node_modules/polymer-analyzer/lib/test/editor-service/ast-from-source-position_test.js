/**
 * Copyright (c) 2015 The Polymer Project Authors. All rights reserved.
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
Object.defineProperty(exports, "__esModule", { value: true });
const chai_1 = require("chai");
const ast_from_source_position_1 = require("../../editor-service/ast-from-source-position");
const html_parser_1 = require("../../html/html-parser");
suite('getLocationInfoForPosition', () => {
    const parser = new html_parser_1.HtmlParser();
    test('works for an empty string', () => {
        const allKindsSpaceSeparated = getAllKindsSpaceSeparated('');
        chai_1.assert.equal(allKindsSpaceSeparated, 'text');
    });
    test('works when just starting a tag', () => {
        const allKindsSpaceSeparated = getAllKindsSpaceSeparated('<t');
        // We assume that you're starting to write an html tag in a text node, so
        // this works.
        chai_1.assert.equal(allKindsSpaceSeparated, 'text text text');
    });
    test('works with a closed tag', () => {
        const allKindsSpaceSeparated = getAllKindsSpaceSeparated('<t></t>');
        chai_1.assert.equal(allKindsSpaceSeparated, 'text tagName tagName text endTag endTag endTag text');
    });
    test('works with an unclosed tag', () => {
        const allKindsSpaceSeparated = getAllKindsSpaceSeparated('<t>');
        chai_1.assert.equal(allKindsSpaceSeparated, 'text tagName tagName text');
    });
    test('works for a closed tag with empty attributes section', () => {
        const allKindsSpaceSeparated = getAllKindsSpaceSeparated('<t ></t>');
        chai_1.assert.equal(allKindsSpaceSeparated, 'text tagName tagName attribute text endTag endTag endTag text');
    });
    test('works for an unclosed tag with empty attributes section', () => {
        const allKindsSpaceSeparated = getAllKindsSpaceSeparated('<t >');
        chai_1.assert.equal(allKindsSpaceSeparated, 'text tagName tagName attribute text');
    });
    test('works for a closed tag with a boolean attribute', () => {
        const allKindsSpaceSeparated = getAllKindsSpaceSeparated('<t a></t>');
        chai_1.assert.equal(allKindsSpaceSeparated, 'text tagName tagName attribute attribute ' +
            'text endTag endTag endTag text');
    });
    test('works for an unclosed tag with a boolean attribute', () => {
        const allKindsSpaceSeparated = getAllKindsSpaceSeparated('<t a>');
        chai_1.assert.equal(allKindsSpaceSeparated, 'text tagName tagName attribute attribute text');
    });
    test('works with an empty attribute value in a closed tag', () => {
        let allKindsSpaceSeparated = getAllKindsSpaceSeparated('<t a=></t>');
        chai_1.assert.equal(allKindsSpaceSeparated, 'text tagName tagName attribute attribute attributeValue text ' +
            'endTag endTag endTag text');
        allKindsSpaceSeparated = getAllKindsSpaceSeparated('<t a=""></t>');
        chai_1.assert.equal(allKindsSpaceSeparated, 'text tagName tagName attribute attribute ' +
            'attributeValue attributeValue attributeValue text ' +
            'endTag endTag endTag text');
        allKindsSpaceSeparated = getAllKindsSpaceSeparated('<t a=\'\'></t>');
        chai_1.assert.equal(allKindsSpaceSeparated, 'text tagName tagName attribute attribute ' +
            'attributeValue attributeValue attributeValue text ' +
            'endTag endTag endTag text');
    });
    test('works with an empty attribute value in an unclosed tag', () => {
        let allKindsSpaceSeparated = getAllKindsSpaceSeparated('<t a=>');
        chai_1.assert.equal(allKindsSpaceSeparated, 'text tagName tagName attribute attribute attributeValue text');
        allKindsSpaceSeparated = getAllKindsSpaceSeparated('<t a="">');
        chai_1.assert.equal(allKindsSpaceSeparated, 'text tagName tagName attribute attribute attributeValue attributeValue attributeValue text');
        allKindsSpaceSeparated = getAllKindsSpaceSeparated('<t a=\'\'>');
        chai_1.assert.equal(allKindsSpaceSeparated, 'text tagName tagName attribute attribute attributeValue attributeValue attributeValue text');
    });
    test(`works with a closed tag with text content`, () => {
        const allKindsSpaceSeparated = getAllKindsSpaceSeparated('<t> </t>');
        chai_1.assert.equal(allKindsSpaceSeparated, 'text tagName tagName text text endTag endTag endTag text');
    });
    test(`works with an unclosed tag with text content`, () => {
        const allKindsSpaceSeparated = getAllKindsSpaceSeparated('<t> ');
        chai_1.assert.equal(allKindsSpaceSeparated, 'text tagName tagName text text');
    });
    test(`works with comments`, () => {
        const allKindsSpaceSeparated = getAllKindsSpaceSeparated('<!-- foo -->');
        chai_1.assert.match(allKindsSpaceSeparated, /^text (comment ){11}text$/);
    });
    test(`works with script tags`, () => {
        let allKindsSpaceSeparated = getAllKindsSpaceSeparated('<script> </script>');
        chai_1.assert.match(allKindsSpaceSeparated, /^text (tagName ){7}scriptTagContents scriptTagContents (endTag ){8}text$/);
        allKindsSpaceSeparated = getAllKindsSpaceSeparated('<script></script>');
        chai_1.assert.match(allKindsSpaceSeparated, /^text (tagName ){7}scriptTagContents (endTag ){8}text$/);
    });
    test(`works with style tags`, () => {
        let allKindsSpaceSeparated = getAllKindsSpaceSeparated('<style> </style>');
        chai_1.assert.match(allKindsSpaceSeparated, /^text (tagName ){6}(styleTagContents ){2}(endTag ){7}text$/);
        allKindsSpaceSeparated = getAllKindsSpaceSeparated('<style></style>');
        chai_1.assert.match(allKindsSpaceSeparated, /^text (tagName ){6}styleTagContents (endTag ){7}text$/);
    });
    test(`it can handle the contents of a template tag`, () => {
        const allKindsSpaceSeparated = getAllKindsSpaceSeparated('<template><t a=""> </t></template>');
        chai_1.assert.match(allKindsSpaceSeparated, /^text (tagName ){9}text (tagName ){2}(attribute ){2}(attributeValue ){3}(text ){2}(endTag ){3}text (endTag ){10}text$/);
    });
    /**
     * Return a space separated string of the `kind` for every location in the
     * given html text.
     *
     * For small documents you can just assert against this string. For larger
     * documents you can write a regexp to express your assertion.
     */
    function getAllKindsSpaceSeparated(text) {
        const doc = parser.parse(text, 'uninteresting file name.html');
        return getEveryPosition(text)
            .map((pos) => ast_from_source_position_1.getLocationInfoForPosition(doc, pos).kind)
            .join(' ');
    }
});
function getEveryPosition(source) {
    const results = [];
    let lineNum = 0;
    for (const line of source.split('\n')) {
        let columnNum = 0;
        for (const _ of line) {
            _.big; // TODO(rictic): tsc complains about unused _
            results.push({ line: lineNum, column: columnNum });
            columnNum++;
        }
        results.push({ line: lineNum, column: columnNum });
        lineNum++;
    }
    return results;
}

//# sourceMappingURL=ast-from-source-position_test.js.map
