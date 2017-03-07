/**
 * @license
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
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : new P(function (resolve) { resolve(result.value); }).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
Object.defineProperty(exports, "__esModule", { value: true });
/// <reference path="../../../node_modules/@types/mocha/index.d.ts" />
const chai_1 = require("chai");
const path = require("path");
const analyzer_1 = require("../../analyzer");
const dependency_graph_1 = require("../../core/dependency-graph");
const fs_url_loader_1 = require("../../url-loader/fs-url-loader");
const chaiAsPromised = require("chai-as-promised");
chai_1.use(chaiAsPromised);
suite('DependencyGraph', () => {
    function assertStringSetsEqual(actual, expected, message) {
        chai_1.assert.deepEqual(Array.from(actual).sort(), Array.from(expected).sort(), message);
    }
    test('can calculate dependants', () => {
        // Testing building up and then tearing back down the graph:
        // base.html -> a.html -> common.html
        // base.html -> b.html -> common.html
        let graph = new dependency_graph_1.DependencyGraph();
        assertStringSetsEqual(graph.getAllDependantsOf('common.html'), []);
        graph.addDocument('a.html', ['common.html']);
        assertStringSetsEqual(graph.getAllDependantsOf('common.html'), ['a.html']);
        graph.addDocument('b.html', ['common.html']);
        assertStringSetsEqual(graph.getAllDependantsOf('common.html'), ['a.html', 'b.html']);
        graph.addDocument('base.html', ['a.html', 'b.html']);
        assertStringSetsEqual(graph.getAllDependantsOf('common.html'), ['a.html', 'b.html', 'base.html']);
        graph = graph.invalidatePaths(['a.html']);
        assertStringSetsEqual(graph.getAllDependantsOf('common.html'), ['b.html', 'base.html']);
        graph = graph.invalidatePaths(['b.html']);
        assertStringSetsEqual(graph.getAllDependantsOf('common.html'), []);
    });
    /**
     * Like many integration tests this is a bit dirty, but it catches many
     * interesting bugs in the way that we construct the dependency graph in
     * practice.
     */
    suite('as used in the Analyzer', () => {
        let analyzer;
        setup(() => {
            analyzer = new analyzer_1.Analyzer({ urlLoader: new fs_url_loader_1.FSUrlLoader(path.join(__dirname, '..', 'static')) });
        });
        function assertImportersOf(path, expectedDependants) {
            assertStringSetsEqual(analyzer['_context']['_cache']['dependencyGraph'].getAllDependantsOf(path), expectedDependants);
        }
        test('works with a basic document with no dependencies', () => __awaiter(this, void 0, void 0, function* () {
            yield analyzer.analyze('dependencies/leaf.html');
            assertImportersOf('dependencies/leaf.html', []);
        }));
        test('works with a simple tree of dependencies', () => __awaiter(this, void 0, void 0, function* () {
            yield analyzer.analyze('dependencies/root.html');
            assertImportersOf('dependencies/root.html', []);
            assertImportersOf('dependencies/leaf.html', ['dependencies/root.html']);
            assertImportersOf('dependencies/subfolder/subfolder-sibling.html', [
                'dependencies/subfolder/in-folder.html',
                'dependencies/inline-and-imports.html',
                'dependencies/root.html'
            ]);
        }));
    });
    suite('whenReady', () => {
        test('resolves for a single added document', () => {
            const graph = new dependency_graph_1.DependencyGraph();
            chai_1.assert.isFulfilled(graph.whenReady('a'));
            graph.addDocument('a', []);
        });
        test('resolves for a single rejected document', () => {
            const graph = new dependency_graph_1.DependencyGraph();
            const done = chai_1.assert.isFulfilled(graph.whenReady('a'));
            graph.rejectDocument('a', new Error('because'));
            return done;
        });
        test('resolves for a document with an added dependency', () => {
            const graph = new dependency_graph_1.DependencyGraph();
            const done = chai_1.assert.isFulfilled(graph.whenReady('a'));
            graph.addDocument('a', ['b']);
            graph.addDocument('b', []);
            return done;
        });
        test('resolves for a document with a rejected dependency', () => {
            const graph = new dependency_graph_1.DependencyGraph();
            const done = chai_1.assert.isFulfilled(graph.whenReady('a'));
            graph.addDocument('a', ['b']);
            graph.rejectDocument('b', new Error('because'));
            return done;
        });
        test('resolves for a simple cycle', () => {
            const graph = new dependency_graph_1.DependencyGraph();
            const promises = [
                chai_1.assert.isFulfilled(graph.whenReady('a')),
                chai_1.assert.isFulfilled(graph.whenReady('b'))
            ];
            graph.addDocument('a', ['b']);
            graph.addDocument('b', ['a']);
            return Promise.all(promises);
        });
        test('does not resolve early for a cycle with a leg', () => __awaiter(this, void 0, void 0, function* () {
            const graph = new dependency_graph_1.DependencyGraph();
            let cResolved = false;
            const aReady = graph.whenReady('a').then(() => {
                chai_1.assert.isTrue(cResolved);
            });
            const bReady = graph.whenReady('b').then(() => {
                chai_1.assert.isTrue(cResolved);
            });
            graph.addDocument('a', ['b', 'c']);
            graph.addDocument('b', ['a']);
            yield Promise.resolve();
            cResolved = true;
            graph.addDocument('c', []);
            yield Promise.all([aReady, bReady]);
        }));
    });
});

//# sourceMappingURL=dependency-graph_test.js.map
