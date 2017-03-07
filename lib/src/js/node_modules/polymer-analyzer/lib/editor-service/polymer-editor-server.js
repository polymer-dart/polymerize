#!/usr/bin/env node
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
const util = require("util");
const fs_url_loader_1 = require("../url-loader/fs-url-loader");
const package_url_resolver_1 = require("../url-loader/package-url-resolver");
const local_editor_service_1 = require("./local-editor-service");
const split = require("split");
/**
 * Handles decoded Requests, dispatching them to a local editor service.
 */
class EditorServer {
    handleMessage(message) {
        return __awaiter(this, void 0, void 0, function* () {
            if (message.kind === 'init') {
                if (this._localEditorService) {
                    throw new Error('Already initialized!');
                }
                this._localEditorService = new local_editor_service_1.LocalEditorService({
                    urlLoader: new fs_url_loader_1.FSUrlLoader(message.basedir),
                    urlResolver: new package_url_resolver_1.PackageUrlResolver()
                });
                return;
            }
            const localEditorService = this._localEditorService;
            if (!localEditorService) {
                throw new Error(`Must send an 'init' message before any others. ` +
                    `Received '${message.kind}' message before 'init'.`);
            }
            switch (message.kind) {
                case 'getWarningsFor':
                    return localEditorService.getWarningsForFile(message.localPath);
                case 'fileChanged':
                    yield localEditorService.fileChanged(message.localPath, message.contents);
                    return;
                case 'getDefinitionFor':
                    return localEditorService.getDefinitionForFeatureAtPosition(message.localPath, message.position);
                case 'getDocumentationFor':
                    return localEditorService.getDocumentationAtPosition(message.localPath, message.position);
                case 'getTypeaheadCompletionsFor':
                    return localEditorService.getTypeaheadCompletionsAtPosition(message.localPath, message.position);
                case '_clearCaches':
                    return localEditorService._clearCaches();
                default:
                    const never = message;
                    throw new Error(`Got unknown kind of message: ${util.inspect(never)}`);
            }
        });
    }
}
const server = new EditorServer();
// stdin/stdout interface
process.stdin.setEncoding('utf8');
process.stdin.resume();
process.stdin.pipe(split()).on('data', function (line) {
    return __awaiter(this, void 0, void 0, function* () {
        if (line.trim() === '') {
            return;
        }
        let result;
        let id = undefined;
        try {
            const request = JSON.parse(line);
            id = request.id;
            result = yield getSettledValue(request.value);
        }
        catch (e) {
            if (id == null) {
                id = -1;
            }
            result = {
                kind: 'rejection',
                rejection: e.message || e.stack || e.toString()
            };
        }
        /** Have a respond function for type checking of ResponseWrapper */
        function respond(response) {
            process.stdout.write(JSON.stringify(response) + '\n');
        }
        respond({ id, value: result });
    });
});
// node child_process.fork() IPC interface
process.on('message', function (request) {
    return __awaiter(this, void 0, void 0, function* () {
        const result = yield getSettledValue(request.value);
        /** Have a respond function for type checking of ResponseWrapper */
        function respond(response) {
            process.send(response);
        }
        respond({ id: request.id, value: result });
    });
});
/**
 * Calls into the server and converts its responses into SettledValues.
 */
function getSettledValue(request) {
    return __awaiter(this, void 0, void 0, function* () {
        try {
            const value = yield server.handleMessage(request);
            return { kind: 'resolution', resolution: value };
        }
        catch (e) {
            return { kind: 'rejection', rejection: e.message || e.stack || e.toString() };
        }
    });
}

//# sourceMappingURL=polymer-editor-server.js.map
