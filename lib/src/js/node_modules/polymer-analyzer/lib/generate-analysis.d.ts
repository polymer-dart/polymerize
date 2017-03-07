import * as jsonschema from 'jsonschema';
import { Analysis } from './analysis-format';
import { Document } from './model/document';
import { Feature } from './model/feature';
import { Element as ResolvedElement, ElementMixin as ResolvedMixin } from './model/model';
import { Package } from './model/package';
export declare type ElementOrMixin = ResolvedElement | ResolvedMixin;
export declare type Filter = (feature: Feature) => boolean;
export declare function generateAnalysis(input: Package | Document[], packagePath: string, filter?: Filter): Analysis;
export declare class ValidationError extends Error {
    errors: jsonschema.ValidationError[];
    constructor(result: jsonschema.ValidatorResult);
}
/**
 * Throws if the given object isn't a valid AnalyzedPackage according to
 * the JSON schema.
 */
export declare function validateAnalysis(analyzedPackage: Analysis | null | undefined): void;
