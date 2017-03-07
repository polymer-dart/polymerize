import * as estree from 'estree';
import { ScannedEvent, SourceRange } from '../model/model';
/**
 * Returns whether an Espree node matches a particular object path.
 *
 * e.g. you have a MemberExpression node, and want to see whether it represents
 * `Foo.Bar.Baz`:
 *    matchesCallExpressio
    (node, ['Foo', 'Bar', 'Baz'])
 *
 * @param {ESTree.Node} expression The Espree node to match against.
 * @param {Array<string>} path The path to look for.
 */
export declare function matchesCallExpression(expression: estree.MemberExpression, path: string[]): boolean;
/**
 * @param {Node} key The node representing an object key or expression.
 * @return {string} The name of that key.
 */
export declare function objectKeyToString(key: estree.Node): string | undefined;
export declare const CLOSURE_CONSTRUCTOR_MAP: {
    'Boolean': string;
    'Number': string;
    'String': string;
};
/**
 * AST expression -> Closure type.
 *
 * Accepts literal values, and native constructors.
 *
 * @param {Node} node An Espree expression node.
 * @return {string} The type of that expression, in Closure terms.
 */
export declare function closureType(node: estree.Node, sourceRange: SourceRange): string;
export declare function getAttachedComment(node: estree.Node): string | undefined;
/**
 * Returns all comments from a tree defined with @event.
 */
export declare function getEventComments(node: estree.Node): ScannedEvent[];
export declare function getPropertyValue(node: estree.ObjectExpression, name: string): estree.Node | undefined;
export declare function isFunctionType(node: estree.Node): node is estree.Function;
