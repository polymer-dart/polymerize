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
Object.defineProperty(exports, "__esModule", { value: true });
const ast_value_1 = require("../javascript/ast-value");
const analyze_properties_1 = require("./analyze-properties");
const docs = require("./docs");
const js_utils_1 = require("./js-utils");
function getStaticGetterValue(node, name) {
    const candidates = node.body.body.filter((n) => n.type === 'MethodDefinition' && n.static === true &&
        n.kind === 'get' && ast_value_1.getIdentifierName(n.key) === name);
    const getter = candidates.length === 1 && candidates[0];
    if (!getter) {
        return undefined;
    }
    // TODO(justinfagnani): consider generating warnings for these checks
    const getterBody = getter.value.body;
    if (getterBody.body.length !== 1) {
        // not a single statement function
        return undefined;
    }
    if (getterBody.body[0].type !== 'ReturnStatement') {
        // we only support a return statement
        return undefined;
    }
    const returnStatement = getterBody.body[0];
    return returnStatement.argument;
}
function getIsValue(node) {
    const getterValue = getStaticGetterValue(node, 'is');
    if (!getterValue || getterValue.type !== 'Literal') {
        // we only support literals
        return undefined;
    }
    if (typeof getterValue.value !== 'string') {
        return undefined;
    }
    return getterValue.value;
}
exports.getIsValue = getIsValue;
/**
 * Returns the properties defined in a Polymer config object literal.
 */
function getProperties(node, document) {
    const propertiesNode = getStaticGetterValue(node, 'properties');
    return propertiesNode ? analyze_properties_1.analyzeProperties(propertiesNode, document) : [];
}
exports.getProperties = getProperties;
function getMethods(node, document) {
    return node.body.body
        .filter((n) => n.type === 'MethodDefinition' && n.static === false &&
        n.kind === 'method')
        .map((m) => {
        return docs.annotate(js_utils_1.toScannedMethod(m, document.sourceRangeForNode(m)));
    });
}
exports.getMethods = getMethods;

//# sourceMappingURL=polymer2-config.js.map
