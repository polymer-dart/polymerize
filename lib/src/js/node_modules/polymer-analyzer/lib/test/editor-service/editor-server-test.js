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
const child_process = require("child_process");
const path = require("path");
const util = require("util");
const test_utils_1 = require("../test-utils");
const split = require("split");
const pathToServer = path.join(__dirname, '../../editor-service/polymer-editor-server.js');
suite('RemoteEditorService', () => {
    /**
     * These are the tests. We run these tests using a few different ways of
     * communicating with the server.
     */
    function editorServiceInterfaceTests(sendRequest, getNextResponse) {
        const initMessage = {
            kind: 'init',
            basedir: `${path.join(__dirname, 'static')}`
        };
        const getWarningsMessage = {
            kind: 'getWarningsFor',
            localPath: 'malformed.html'
        };
        test('can create and initialize', () => __awaiter(this, void 0, void 0, function* () {
            yield sendRequest({ id: 0, value: initMessage });
            const response = yield getNextResponse(0);
            chai_1.assert.deepEqual(response, undefined);
        }));
        test('initializing twice is an error', () => __awaiter(this, void 0, void 0, function* () {
            yield sendRequest({ id: 0, value: initMessage });
            yield getNextResponse(0);
            yield sendRequest({ id: 1, value: initMessage });
            const errorMessage = yield test_utils_1.invertPromise(getNextResponse(1));
            chai_1.assert.equal(errorMessage, 'Already initialized!');
        }));
        test('the first request must be initialization', () => __awaiter(this, void 0, void 0, function* () {
            yield sendRequest({ id: 0, value: getWarningsMessage });
            const errorMessage = yield test_utils_1.invertPromise(getNextResponse(0));
            chai_1.assert.equal(errorMessage, `Must send an 'init' message before any others. Received ` +
                `'getWarningsFor' message before 'init'.`);
        }));
        const testName = 'can perform editor service functions once initialized';
        test(testName, () => __awaiter(this, void 0, void 0, function* () {
            yield sendRequest({ id: 0, value: initMessage });
            yield getNextResponse(0);
            yield sendRequest({ id: 1, value: getWarningsMessage });
            const warnings = yield getNextResponse(1);
            chai_1.assert.deepEqual(warnings, [{
                    code: 'parse-error',
                    message: 'Unexpected token <',
                    severity: 0,
                    sourceRange: {
                        file: 'malformed.html',
                        start: { line: 266, column: 0 },
                        end: { line: 266, column: 0 }
                    }
                }]);
        }));
    }
    suite('from node with child_process.fork() and process.send() for IPC', () => {
        let child;
        setup(() => {
            child = child_process.fork(pathToServer);
        });
        teardown(() => {
            child.kill();
        });
        function sendRequest(request) {
            return __awaiter(this, void 0, void 0, function* () {
                child.send(request);
            });
        }
        ;
        function getNextResponse(expectedId) {
            return __awaiter(this, void 0, void 0, function* () {
                const message = yield new Promise((resolve) => {
                    child.once('message', function (msg) {
                        resolve(msg);
                    });
                });
                chai_1.assert.equal(message.id, expectedId);
                if (message.value.kind === 'resolution') {
                    return message.value.resolution;
                }
                if (message.value.kind === 'rejection') {
                    throw message.value.rejection;
                }
                throw new Error(`Response with unexpected kind: ${util.inspect(message.value)}`);
            });
        }
        ;
        editorServiceInterfaceTests(sendRequest, getNextResponse);
    });
    suite('from the command line with stdin and stdout', () => {
        let child;
        let lines;
        setup(() => {
            child = child_process.spawn('node', [pathToServer], { stdio: ['pipe', 'pipe', 'pipe'] });
            child.stdout.setEncoding('utf8');
            child.stdout.resume();
            lines = child.stdout.pipe(split());
        });
        teardown(() => {
            child.kill();
        });
        function sendRequest(message) {
            return __awaiter(this, void 0, void 0, function* () {
                return new Promise((resolve, reject) => {
                    child.stdin.write(JSON.stringify(message) + '\n', (err) => {
                        err ? reject(err) : resolve();
                    });
                });
            });
        }
        ;
        function getNextResponse(expectedId) {
            return __awaiter(this, void 0, void 0, function* () {
                const line = yield new Promise((resolve) => lines.once('data', resolve));
                const message = JSON.parse(line);
                chai_1.assert.equal(message.id, expectedId);
                if (message.value.kind === 'resolution') {
                    return message.value.resolution;
                }
                else if (message.value.kind === 'rejection') {
                    throw message.value.rejection;
                }
                throw new Error(`Response with unexpected kind: ${util.inspect(message.value)}`);
            });
        }
        editorServiceInterfaceTests(sendRequest, getNextResponse);
    });
});

//# sourceMappingURL=editor-server-test.js.map
