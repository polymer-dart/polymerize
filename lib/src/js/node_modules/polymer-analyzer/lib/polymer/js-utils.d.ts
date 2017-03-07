import * as estree from 'estree';
import * as jsdoc from '../javascript/jsdoc';
import { Privacy, ScannedMethod, SourceRange } from '../model/model';
import { ScannedPolymerProperty } from './polymer-element';
/**
 * Create a ScannedProperty object from an estree Property AST node.
 */
export declare function toScannedPolymerProperty(node: estree.Property | estree.MethodDefinition, sourceRange: SourceRange): ScannedPolymerProperty;
/**
 * Create a ScannedMethod object from an estree Property AST node.
 */
export declare function toScannedMethod(node: estree.Property | estree.MethodDefinition, sourceRange: SourceRange): ScannedMethod;
export declare function getOrInferPrivacy(name: string, annotation: jsdoc.Annotation | undefined, privateUnlessDocumented: boolean): Privacy;
