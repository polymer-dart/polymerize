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
const analyzer_1 = require("../analyzer");
const warning_printer_1 = require("../warning/warning-printer");
class UnexpectedResolutionError extends Error {
    constructor(message, resolvedValue) {
        super(message);
        this.resolvedValue = resolvedValue;
    }
}
exports.UnexpectedResolutionError = UnexpectedResolutionError;
function invertPromise(promise) {
    return __awaiter(this, void 0, void 0, function* () {
        let value;
        try {
            value = yield promise;
        }
        catch (e) {
            return e;
        }
        throw new UnexpectedResolutionError('Inverted Promise resolved', value);
    });
}
exports.invertPromise = invertPromise;
class TestUrlLoader {
    constructor(files) {
        this.files = files;
    }
    canLoad(url) {
        return url in this.files;
    }
    load(url) {
        return __awaiter(this, void 0, void 0, function* () {
            if (this.canLoad(url)) {
                return this.files[url];
            }
            throw new Error(`cannot load file ${url}`);
        });
    }
}
exports.TestUrlLoader = TestUrlLoader;
/**
 * Used for asserting that warnings or source ranges correspond to the right
 * parts of the source code.
 *
 * Non-test code probably wants WarningPrinter instead.
 */
class CodeUnderliner {
    constructor(urlLoader) {
        this.warningPrinter =
            new warning_printer_1.WarningPrinter(null, { analyzer: new analyzer_1.Analyzer({ urlLoader }) });
    }
    static withMapping(url, contents) {
        return new CodeUnderliner(new TestUrlLoader({ [url]: contents }));
    }
    underline(references) {
        return __awaiter(this, void 0, void 0, function* () {
            if (!Array.isArray(references)) {
                if (references === undefined) {
                    return 'No source range given.';
                }
                const sourceRange = isWarning(references) ? references.sourceRange : references;
                return '\n' + (yield this.warningPrinter.getUnderlinedText(sourceRange));
            }
            return Promise.all(references.map((ref) => this.underline(ref)));
        });
    }
}
exports.CodeUnderliner = CodeUnderliner;
function isWarning(wOrS) {
    return 'code' in wOrS;
}

//# sourceMappingURL=test-utils.js.map
