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
/// <reference path="../../node_modules/@types/mocha/index.d.ts" />
const chai_1 = require("chai");
const utils_1 = require("../utils");
const chaiAsPromised = require("chai-as-promised");
chai_1.use(chaiAsPromised);
suite('parseUrl', () => {
    function testUrl(url, properties) {
        const urlObject = utils_1.parseUrl(url);
        for (const key in properties) {
            if (!properties.hasOwnProperty(key)) {
                continue;
            }
            chai_1.assert.equal(urlObject[key], properties[key], `${url} property ${key}`);
        }
    }
    test('parses urls that are absolute paths', () => {
        testUrl('/abs/path', { protocol: null, hostname: null, pathname: '/abs/path' });
        testUrl('/abs/path?query=string#hash', {
            protocol: null,
            hostname: null,
            pathname: '/abs/path',
            hash: '#hash',
            search: '?query=string',
        });
    });
    test('parses urls without protocol', () => {
        testUrl('//host/path', {
            protocol: undefined,
            hostname: 'host',
            pathname: '/path',
        });
        testUrl('//host', {
            protocol: undefined,
            hostname: 'host',
            pathname: null,
        });
    });
    test('parses urls that have protocols', () => {
        testUrl('https://host/path', {
            protocol: 'https:',
            hostname: 'host',
            pathname: '/path',
        });
    });
});
suite('Deferred', () => {
    test('resolves', () => __awaiter(this, void 0, void 0, function* () {
        const deferred = new utils_1.Deferred();
        const done = chai_1.assert.becomes(deferred.promise, 'foo');
        deferred.resolve('foo');
        yield done;
    }));
    test('rejects', () => __awaiter(this, void 0, void 0, function* () {
        const deferred = new utils_1.Deferred();
        const done = chai_1.assert.isRejected(deferred.promise, 'foo');
        deferred.reject(new Error('foo'));
        yield done;
    }));
    test('resolves only once', () => __awaiter(this, void 0, void 0, function* () {
        const deferred = new utils_1.Deferred();
        deferred.resolve('foo');
        try {
            deferred.resolve('bar');
            chai_1.assert.fail();
        }
        catch (e) {
            // pass
        }
        try {
            deferred.reject(new Error('bar'));
            chai_1.assert.fail();
        }
        catch (e) {
            // pass
        }
    }));
    test('rejects', () => __awaiter(this, void 0, void 0, function* () {
        const deferred = new utils_1.Deferred();
        deferred.reject(new Error('foo'));
        deferred.promise.catch((_) => { });
        try {
            deferred.resolve('bar');
            chai_1.assert.fail();
        }
        catch (e) {
            // pass
        }
        try {
            deferred.reject(new Error('bar'));
            chai_1.assert.fail();
        }
        catch (e) {
            // pass
        }
    }));
});

//# sourceMappingURL=utils_test.js.map
