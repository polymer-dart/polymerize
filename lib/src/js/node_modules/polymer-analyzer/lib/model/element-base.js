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
/**
 * Base class for ScannedElement and ScannedElementMixin.
 */
class ScannedElementBase {
    constructor() {
        this.properties = [];
        this.attributes = [];
        this.description = '';
        this.summary = '';
        this.demos = [];
        this.events = [];
        this.warnings = [];
        this['slots'] = [];
        this.mixins = [];
    }
    applyHtmlComment(commentText) {
        this.description = this.description || commentText || '';
    }
    resolve(_document) {
        throw new Error('abstract');
    }
}
exports.ScannedElementBase = ScannedElementBase;
class Slot {
    constructor(name, range) {
        this.name = name;
        this.range = range;
    }
}
exports.Slot = Slot;
/**
 * Base class for Element and ElementMixin.
 */
class ElementBase {
    constructor() {
        this.properties = [];
        this.attributes = [];
        this.methods = [];
        this.description = '';
        this.summary = '';
        this.demos = [];
        this.events = [];
        this.kinds = new Set(['element']);
        this.warnings = [];
        this['slots'] = [];
        /**
         * Mixins that this class declares with `@mixes`.
         *
         * Mixins are applied linearly after the superclass, in order from first
         * to last. Mixins that compose other mixins will be flattened into a
         * single list. A mixin can be applied more than once, each time its
         * members override those before it in the prototype chain.
         */
        this.mixins = [];
    }
    get identifiers() {
        throw new Error('abstract');
    }
    emitMetadata() {
        return {};
    }
    emitPropertyMetadata(_property) {
        return {};
    }
    emitAttributeMetadata(_attribute) {
        return {};
    }
    emitMethodMetadata(_property) {
        return {};
    }
    emitEventMetadata(_event) {
        return {};
    }
}
exports.ElementBase = ElementBase;

//# sourceMappingURL=element-base.js.map
