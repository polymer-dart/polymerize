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
const child_process = require("child_process");
const path = require("path");
const util = require("util");
const editor_service_1 = require("./editor-service");
/**
 * Runs the editor server in a new node process and exposes a promise based
 * request API for communicating with it.
 */
class EditorServerChannel {
    constructor() {
        this._idCounter = 0;
        this._outstandingRequests = new Map();
        const serverJsFile = path.join(__dirname, 'polymer-editor-server.js');
        this._child = child_process.fork(serverJsFile, [], {});
        this._child.addListener('message', (m) => this._handleResponse(m));
    }
    request(req) {
        return __awaiter(this, void 0, void 0, function* () {
            const id = this._idCounter++;
            const deferred = new Deferred();
            this._outstandingRequests.set(id, deferred);
            yield this._sendRequest(id, req);
            return deferred.promise;
        });
    }
    _handleResponse(response) {
        const deferred = this._outstandingRequests.get(response.id);
        if (!deferred) {
            console.error(`EditorServer returned a response for unknown/previously` +
                ` settled request id: ${response.id}`);
            return;
        }
        switch (response.value.kind) {
            case 'resolution':
                return deferred.resolve(response.value.resolution);
            case 'rejection':
                return deferred.reject(response.value.rejection);
            default:
                const never = response.value;
                throw new Error(`Got unknown kind of response: ${util.inspect(never)}`);
        }
    }
    _sendRequest(id, value) {
        return __awaiter(this, void 0, void 0, function* () {
            const request = { id, value };
            yield new Promise((resolve, reject) => {
                this._child.send(request, (err) => err ? reject(err) : resolve());
            });
        });
    }
    dispose() {
        this._child.kill();
    }
}
/**
 * Runs in-process and communicates to the editor server, which
 * runs in a child process. Exposes the same interface as the
 * LocalEditorService.
 */
class RemoteEditorService extends editor_service_1.EditorService {
    constructor(basedir) {
        super();
        this._channel = new EditorServerChannel();
        this._channel.request({ kind: 'init', basedir });
    }
    getWarningsForFile(localPath) {
        return __awaiter(this, void 0, void 0, function* () {
            return this._channel.request({ kind: 'getWarningsFor', localPath });
        });
    }
    fileChanged(localPath, contents) {
        return __awaiter(this, void 0, void 0, function* () {
            return this._channel.request({ kind: 'fileChanged', localPath, contents });
        });
    }
    getDocumentationAtPosition(localPath, position) {
        return __awaiter(this, void 0, void 0, function* () {
            return this._channel.request({ kind: 'getDocumentationFor', localPath, position });
        });
    }
    getDefinitionForFeatureAtPosition(localPath, position) {
        return __awaiter(this, void 0, void 0, function* () {
            return this._channel.request({ kind: 'getDefinitionFor', localPath, position });
        });
    }
    getTypeaheadCompletionsAtPosition(localPath, position) {
        return __awaiter(this, void 0, void 0, function* () {
            return this._channel.request({ kind: 'getTypeaheadCompletionsFor', localPath, position });
        });
    }
    _clearCaches() {
        return __awaiter(this, void 0, void 0, function* () {
            return this._channel.request({ kind: '_clearCaches' });
        });
    }
    dispose() {
        this._channel.dispose();
    }
}
exports.RemoteEditorService = RemoteEditorService;
class Deferred {
    constructor() {
        this.promise = new Promise((res, rej) => {
            this.resolve = res;
            this.reject = rej;
        });
    }
}

//# sourceMappingURL=remote-editor-service.js.map
