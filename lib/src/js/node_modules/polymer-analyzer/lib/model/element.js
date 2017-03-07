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
Object.defineProperty(exports, "__esModule", { value: true });
const element_base_1 = require("./element-base");
class ScannedElement extends element_base_1.ScannedElementBase {
    constructor() {
        super();
    }
    applyHtmlComment(commentText) {
        this.description = this.description || commentText || '';
    }
    resolve(_document) {
        const element = new Element();
        Object.assign(element, this);
        return element;
    }
}
exports.ScannedElement = ScannedElement;
class Element extends element_base_1.ElementBase {
    constructor() {
        super();
    }
    get identifiers() {
        const result = new Set();
        if (this.tagName) {
            result.add(this.tagName);
        }
        if (this.className) {
            result.add(this.className);
        }
        return result;
    }
}
exports.Element = Element;

//# sourceMappingURL=element.js.map
