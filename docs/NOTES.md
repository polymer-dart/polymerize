# Pits and falls

This project is based on a number of conjectures and assumptions about the
current `DDC` way of working and the code generation algorithm.

All these conjectures are reasonable and probably will be maintained during
the evolution of `DDC` but there is no official statement on that so they may change
in the future.

This means that there's an moderate chances of introducing breaking changes
as a concenquence of trying to adapt to tool to changes of `DDC`.

And of course this also means that there a minimal but not zero possibility that
this tool will stop working at all and forever if it becomes intrinsically
inconciviable with `DDC`. In that case there's always the option of forking DDC
but this will means basically creating a new language (DDC is what adds actual semantic to Dart)

The most important pillars on which `polymerize` is based are explained in the following paragraphs.

## Dart <-> JS Interoparability

At the time of this writing the code generation algorithm (and to be honest there some declaration
of intent about this in the `DCC` docs) tries to map `Dart` construct to `ES6` constructs as much
closer as possible.

This means for instance that :
 - a dart class is mapped to an ES6 class
 - a method is mapped to an ES6 method with the same name
 - getters and setters are mapped to ES6 getters and setters with the same name
 - a dart field is mapped to a field in an ES6 class (i.e. an assignament in the constructor).

Private names are replaced with `Symbol`, while the constructor is mapped with a method called `new` that the actual ES6 concstructor will call.

This almost perfect correspondance between Dart and generated ES6 code makes it possible for instance to avoid any need of reflection of the Dart
class in order to use them for data biding or event handling, they will be used directly by polymer itself.

In `dart2js` this does not stand so we need reflection in order to emulate properties setter and getters to dart one and invoke methods.

## Reflection

`DDC` saves metadata on classes. I figure the main reason is to implement runtime type checks and ensure strong semantic. This info can be used for reflection.
`polymerize` uses that information in order to fix some mapping issues.

## HtmlElement

`poylmerize` leverages the current way of handling native browser element to Dart classes (through `registerExtension`). There's an high chances this mechanism will be changed.
