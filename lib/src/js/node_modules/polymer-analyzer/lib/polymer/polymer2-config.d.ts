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
import * as estree from 'estree';
import { JavaScriptDocument } from '../javascript/javascript-document';
import { ScannedMethod } from '../model/model';
import { ScannedPolymerProperty } from './polymer-element';
export declare function getIsValue(node: estree.ClassDeclaration | estree.ClassExpression): string | undefined;
/**
 * Returns the properties defined in a Polymer config object literal.
 */
export declare function getProperties(node: estree.ClassDeclaration | estree.ClassExpression, document: JavaScriptDocument): ScannedPolymerProperty[];
export declare function getMethods(node: estree.ClassDeclaration | estree.ClassExpression, document: JavaScriptDocument): ScannedMethod[];
