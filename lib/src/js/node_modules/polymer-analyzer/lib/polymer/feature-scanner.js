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
const esutil = require("../javascript/esutil");
const js_utils_1 = require("./js-utils");
function featureScanner(document) {
    /** The features we've found. */
    const features = [];
    function _extractDesc(feature, _node, parent) {
        feature.description = esutil.getAttachedComment(parent) || '';
    }
    function _extractProperties(feature, node, _parent) {
        const featureNode = node.arguments[0];
        if (featureNode.type !== 'ObjectExpression') {
            console.warn('Expected first argument to Polymer.Base._addFeature to be an object.', 'Got', featureNode.type, 'instead.');
            return;
        }
        if (!featureNode.properties) {
            return;
        }
        const polymerProps = featureNode.properties.map((p) => js_utils_1.toScannedPolymerProperty(p, document.sourceRangeForNode(p)));
        for (const prop of polymerProps) {
            feature.addProperty(prop);
        }
    }
    const visitors = {
        enterCallExpression: function enterCallExpression(node, parent) {
            const isAddFeatureCall = esutil.matchesCallExpression(node.callee, ['Polymer', 'Base', '_addFeature']);
            if (!isAddFeatureCall) {
                return;
            }
            const feature = {};
            _extractDesc(feature, node, parent);
            _extractProperties(feature, node, parent);
            features.push(feature);
        },
    };
    return { visitors, features };
}
exports.featureScanner = featureScanner;
;

//# sourceMappingURL=feature-scanner.js.map
