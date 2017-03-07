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
const chai_1 = require("chai");
const path = require("path");
const analyzer_1 = require("../../analyzer");
const polymer2_element_scanner_1 = require("../../polymer/polymer2-element-scanner");
const polymer2_mixin_scanner_1 = require("../../polymer/polymer2-mixin-scanner");
const fs_url_loader_1 = require("../../url-loader/fs-url-loader");
suite('PolymerElement', () => {
    const testFilesDir = path.resolve(__dirname, '../static/polymer2/');
    const urlLoader = new fs_url_loader_1.FSUrlLoader(testFilesDir);
    const analyzer = new analyzer_1.Analyzer({
        urlLoader: urlLoader,
        scanners: new Map([[
                'js',
                [
                    new polymer2_element_scanner_1.Polymer2ElementScanner(),
                    new polymer2_mixin_scanner_1.Polymer2MixinScanner(),
                ]
            ]])
    });
    function getElements(filename) {
        return __awaiter(this, void 0, void 0, function* () {
            const document = yield analyzer.analyze(filename);
            const elements = document.getByKind('polymer-element');
            return elements;
        });
    }
    ;
    function getTestProps(element) {
        return {
            className: element.className,
            superClass: element.superClass && element.superClass.identifier,
            tagName: element.tagName,
            description: element.description,
            properties: element.properties.map((p) => ({
                name: p.name,
                inheritedFrom: p.inheritedFrom,
            })),
            attributes: element.attributes.map((a) => ({
                name: a.name,
            })),
            methods: element.methods.map((m) => ({ name: m.name, params: m.params, return: m.return })),
        };
    }
    test('Scans base and sub-class', () => __awaiter(this, void 0, void 0, function* () {
        const elements = yield getElements('test-element-3.js');
        const elementData = Array.from(elements).map(getTestProps);
        chai_1.assert.deepEqual(elementData, [
            {
                tagName: undefined,
                className: 'BaseElement',
                superClass: 'Polymer.Element',
                description: '',
                properties: [{
                        name: 'foo',
                        inheritedFrom: undefined,
                    }],
                attributes: [{
                        name: 'foo',
                    }],
                methods: [],
            },
            {
                tagName: 'sub-element',
                className: 'SubElement',
                superClass: 'BaseElement',
                description: '',
                properties: [
                    {
                        name: 'foo',
                        inheritedFrom: 'BaseElement',
                    },
                    {
                        name: 'bar',
                        inheritedFrom: undefined,
                    },
                ],
                attributes: [
                    {
                        name: 'foo',
                    },
                    {
                        name: 'bar',
                    },
                ],
                methods: [],
            },
        ]);
    }));
    test('Elements inherit from mixins and base classes', () => __awaiter(this, void 0, void 0, function* () {
        const elements = yield getElements('test-element-7.js');
        const elementData = Array.from(elements).map(getTestProps);
        chai_1.assert.deepEqual(elementData, [
            {
                tagName: undefined,
                className: 'BaseElement',
                superClass: 'Polymer.Element',
                description: '',
                properties: [
                    {
                        name: 'one',
                        inheritedFrom: undefined,
                    },
                    {
                        name: 'two',
                        inheritedFrom: undefined,
                    }
                ],
                attributes: [
                    {
                        name: 'one',
                    },
                    {
                        name: 'two',
                    }
                ],
                methods: [
                    { name: 'customMethodOnBaseElement', params: [], return: undefined }
                ],
            },
            {
                tagName: 'sub-element',
                className: 'SubElement',
                superClass: 'BaseElement',
                description: '',
                properties: [
                    {
                        name: 'one',
                        inheritedFrom: 'BaseElement',
                    },
                    {
                        name: 'two',
                        inheritedFrom: 'Mixin',
                    },
                    {
                        name: 'three',
                        inheritedFrom: 'Mixin',
                    },
                    {
                        name: 'four',
                        inheritedFrom: undefined,
                    },
                    {
                        inheritedFrom: undefined,
                        name: 'five',
                    }
                ],
                attributes: [
                    {
                        name: 'one',
                    },
                    {
                        name: 'two',
                    },
                    {
                        name: 'three',
                    },
                    {
                        name: 'four',
                    },
                    {
                        name: 'five',
                    }
                ],
                methods: [
                    { name: 'customMethodOnBaseElement', params: [], return: undefined },
                    { name: 'customMethodOnMixin', params: [], return: undefined },
                    { name: 'customMethodOnSubElement', params: [], return: undefined },
                ],
            },
        ]);
    }));
});

//# sourceMappingURL=polymer-element_test.js.map
