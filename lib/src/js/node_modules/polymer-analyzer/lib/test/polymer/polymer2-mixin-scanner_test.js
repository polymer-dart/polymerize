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
const javascript_parser_1 = require("../../javascript/javascript-parser");
const polymer_element_mixin_1 = require("../../polymer/polymer-element-mixin");
const polymer2_mixin_scanner_1 = require("../../polymer/polymer2-mixin-scanner");
const fs_url_loader_1 = require("../../url-loader/fs-url-loader");
const test_utils_1 = require("../test-utils");
suite('Polymer2MixinScanner', () => {
    const testFilesDir = path.resolve(__dirname, '../static/polymer2/');
    const urlLoader = new fs_url_loader_1.FSUrlLoader(testFilesDir);
    const underliner = new test_utils_1.CodeUnderliner(urlLoader);
    function getMixins(filename) {
        return __awaiter(this, void 0, void 0, function* () {
            const file = yield urlLoader.load(filename);
            const parser = new javascript_parser_1.JavaScriptParser();
            const document = parser.parse(file, filename);
            const scanner = new polymer2_mixin_scanner_1.Polymer2MixinScanner();
            const visit = (visitor) => Promise.resolve(document.visit([visitor]));
            const features = yield scanner.scan(document, visit);
            return features.filter((e) => e instanceof polymer_element_mixin_1.ScannedPolymerElementMixin);
        });
    }
    ;
    function getTestProps(mixin) {
        return {
            name: mixin.name,
            description: mixin.description,
            summary: mixin.summary,
            properties: mixin.properties.map((p) => ({
                name: p.name,
            })),
            attributes: mixin.attributes.map((a) => ({
                name: a.name,
            })),
            methods: mixin.methods.map((m) => ({ name: m.name, params: m.params, return: m.return })),
        };
    }
    test('finds mixin function declarations', () => __awaiter(this, void 0, void 0, function* () {
        const mixins = yield getMixins('test-mixin-1.js');
        const mixinData = mixins.map(getTestProps);
        chai_1.assert.deepEqual(mixinData, [{
                name: 'TestMixin',
                description: 'A mixin description',
                summary: 'A mixin summary',
                properties: [{
                        name: 'foo',
                    }],
                attributes: [{
                        name: 'foo',
                    }],
                methods: [],
            }]);
        const underlinedSource = yield underliner.underline(mixins[0].sourceRange);
        chai_1.assert.equal(underlinedSource, `
function TestMixin(superclass) {
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  return class extends superclass {
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    static get properties() {
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      return {
~~~~~~~~~~~~~~
        foo: {
~~~~~~~~~~~~~~
          notify: true,
~~~~~~~~~~~~~~~~~~~~~~~
          type: String,
~~~~~~~~~~~~~~~~~~~~~~~
        },
~~~~~~~~~~
      };
~~~~~~~~
    }
~~~~~
  }
~~~
}
~`);
    }));
    test('finds mixin arrow function expressions', () => __awaiter(this, void 0, void 0, function* () {
        const mixins = yield getMixins('test-mixin-2.js');
        const mixinData = mixins.map(getTestProps);
        chai_1.assert.deepEqual(mixinData, [{
                name: 'Polymer.TestMixin',
                description: 'A mixin description',
                summary: 'A mixin summary',
                properties: [{
                        name: 'foo',
                    }],
                attributes: [{
                        name: 'foo',
                    }],
                methods: [],
            }]);
        const underlinedSource = yield underliner.underline(mixins[0].sourceRange);
        chai_1.assert.equal(underlinedSource, `
const TestMixin = (superclass) => class extends superclass {
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  static get properties() {
~~~~~~~~~~~~~~~~~~~~~~~~~~~
    return {
~~~~~~~~~~~~
      foo: {
~~~~~~~~~~~~
        notify: true,
~~~~~~~~~~~~~~~~~~~~~
        type: String,
~~~~~~~~~~~~~~~~~~~~~
      },
~~~~~~~~
    };
~~~~~~
  }
~~~
}
~`);
    }));
    test('finds mixin function expressions', () => __awaiter(this, void 0, void 0, function* () {
        const mixins = yield getMixins('test-mixin-3.js');
        const mixinData = mixins.map(getTestProps);
        chai_1.assert.deepEqual(mixinData, [{
                name: 'Polymer.TestMixin',
                description: '',
                summary: '',
                properties: [{
                        name: 'foo',
                    }],
                attributes: [{
                        name: 'foo',
                    }],
                methods: [],
            }]);
        const underlinedSource = yield underliner.underline(mixins[0].sourceRange);
        chai_1.assert.equal(underlinedSource, `
const TestMixin = function(superclass) {
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  return class extends superclass {
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    static get properties() {
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      return {
~~~~~~~~~~~~~~
        foo: {
~~~~~~~~~~~~~~
          notify: true,
~~~~~~~~~~~~~~~~~~~~~~~
          type: String,
~~~~~~~~~~~~~~~~~~~~~~~
        },
~~~~~~~~~~
      };
~~~~~~~~
    }
~~~~~
  }
~~~
}
~`);
    }));
    test('finds mixin variable declaration with only name, does not use trailing function', () => __awaiter(this, void 0, void 0, function* () {
        const mixins = yield getMixins('test-mixin-4.js');
        const mixinData = mixins.map(getTestProps);
        chai_1.assert.deepEqual(mixinData, [{
                name: 'Polymer.TestMixin',
                description: '',
                summary: '',
                properties: [],
                attributes: [],
                methods: [],
            }]);
        const underlinedSource = yield underliner.underline(mixins[0].sourceRange);
        chai_1.assert.equal(underlinedSource, `
let TestMixin;
~~~~~~~~~~~~~~`);
    }));
    test('what to do on a class marked @polymerMixin?', () => __awaiter(this, void 0, void 0, function* () {
        const mixins = yield getMixins('test-mixin-5.js');
        const mixinData = mixins.map(getTestProps);
        chai_1.assert.deepEqual(mixinData, []);
    }));
    test('finds mixin function declaration with only name', () => __awaiter(this, void 0, void 0, function* () {
        const mixins = yield getMixins('test-mixin-6.js');
        const mixinData = mixins.map(getTestProps);
        chai_1.assert.deepEqual(mixinData, [{
                name: 'Polymer.TestMixin',
                description: '',
                summary: '',
                properties: [],
                attributes: [],
                methods: [],
            }]);
        const underlinedSource = yield underliner.underline(mixins[0].sourceRange);
        chai_1.assert.equal(underlinedSource, `
function TestMixin() {
~~~~~~~~~~~~~~~~~~~~~~
}
~`);
    }));
    test('finds mixin assigned to a namespace', () => __awaiter(this, void 0, void 0, function* () {
        const mixins = yield getMixins('test-mixin-7.js');
        const mixinData = mixins.map(getTestProps);
        chai_1.assert.deepEqual(mixinData, [{
                name: 'Polymer.TestMixin',
                description: '',
                summary: '',
                properties: [{
                        name: 'foo',
                    }],
                attributes: [{
                        name: 'foo',
                    }],
                methods: [],
            }]);
        const underlinedSource = yield underliner.underline(mixins[0].sourceRange);
        chai_1.assert.equal(underlinedSource, `
Polymer.TestMixin = Polymer.woohoo(function TestMixin(base) {
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  /** @polymerMixinClass */
~~~~~~~~~~~~~~~~~~~~~~~~~~~
  class TestMixin extends base {
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    static get properties() {
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      return {
~~~~~~~~~~~~~~
        foo: {
~~~~~~~~~~~~~~
          notify: true,
~~~~~~~~~~~~~~~~~~~~~~~
          type: String,
~~~~~~~~~~~~~~~~~~~~~~~
        },
~~~~~~~~~~
      };
~~~~~~~~
    };
~~~~~~
  };
~~~~
  return TestMixin;
~~~~~~~~~~~~~~~~~~~
});
~~`);
    }));
    test('properly analyzes nested mixin assignments with memberof tags', () => __awaiter(this, void 0, void 0, function* () {
        const mixins = yield getMixins('test-mixin-8.js');
        const mixinData = mixins.map(getTestProps);
        chai_1.assert.deepEqual(mixinData, [{
                name: 'Polymer.TestMixin',
                description: '',
                summary: '',
                properties: [{
                        name: 'foo',
                    }],
                attributes: [{
                        name: 'foo',
                    }],
                methods: [],
            }]);
    }));
    test('properly analyzes mixin instance and class methods', () => __awaiter(this, void 0, void 0, function* () {
        const mixins = yield getMixins('test-mixin-9.js');
        const mixinData = mixins.map(getTestProps);
        chai_1.assert.deepEqual(mixinData, [
            {
                name: 'TestMixin',
                description: 'A mixin description',
                summary: 'A mixin summary',
                properties: [{
                        name: 'foo',
                    }],
                attributes: [{
                        name: 'foo',
                    }],
                methods: [
                    { name: 'customInstanceFunction', params: [], return: undefined },
                    {
                        name: 'customInstanceFunctionWithJSDoc',
                        params: [], return: undefined,
                    },
                    {
                        name: 'customInstanceFunctionWithParams',
                        params: [{ name: 'a' }, { name: 'b' }, { name: 'c' }], return: undefined,
                    },
                    {
                        name: 'customInstanceFunctionWithParamsAndJSDoc',
                        params: [{ name: 'a' }, { name: 'b' }, { name: 'c' }], return: undefined,
                    },
                    {
                        name: 'customInstanceFunctionWithParamsAndPrivateJSDoc',
                        params: [], return: undefined,
                    },
                ],
            }
        ]);
    }));
});

//# sourceMappingURL=polymer2-mixin-scanner_test.js.map
