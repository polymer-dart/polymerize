# Poylmerize - Polymer 2.0 Dart experimental support

[![Join the chat at https://gitter.im/devc_builder/Lobby](https://badges.gitter.im/devc_builder/Lobby.svg)](https://gitter.im/devc_builder/Lobby?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

This package is a command line tool to build **Polymer 2** components with **DDC** from Dart.

The benefits of this approach compared to the `dart2js` standard `polymer-1.x` are :

 - support for `polymer 2.0-preview` (web components 1.0)
 - using DDC to generate `ES6` output code
 - using [bazel](http://bazel.io) as build system (see also [rules](https://github.com/dam0vm3nt/bazel_polymerize_rules)
 - **dynamic load** of polymer components definitions through `requirejs`
 - **interoperability** with other JS frameworks
 - **Incremental** build (dependencies are built only once)
 - possibility to distribute **ONLY** the build result to thirdy party users and devs
 - simplified API
   - automatic getter and setter (no explicit notify for first level properties)
   - **NO** Annotations required to expose properties
   - **NO** Annotations required to expose methods

## Disclaimer

Actually this tool will now work only for Linux. To be used on macosx should be only a matter of changing some 
builtin path and this will be fixed very soon.

Bazel doesn't work on windows system for now (it depends too much un `bash` to be able to work there) so... sorry guys.

## Install

This tool is actually used internally by bazel rules so you don't need to install it (bazel will do that for you).
All you have to do is start using bazel rules and enjoy. 

If you want to learn more, check out the sample project (see below).

## Usage

A sample project demostrating how to build `polymer-2` components using `polymerize` can be found here :
 - [Sample mini todo APP for Polymer2-Dart-DDC Project](https://github.com/dam0vm3nt/todo_ddc)

See the [README](https://github.com/dam0vm3nt/polymer_dcc/blob/master/README.md) for more information.


### Component definition

This is a sample component definition:

    import 'package:polymer_element/polymer_element.dart';
    import 'package:my_component/other_component.dart' show OtherComponent;

    @PolymerRegister('my-tag',template:'my-tag.html',uses=[OtherComponent])
    class MyTag extends PolymerElement {

      int count = 0;  // <- no need to annotate this !!!

      onClickIt(Event ev,details) {  // <- NO need to annotate this!!!!
        count = count + 1;    // <- no need to call `set` API , magical setter in action here
      }

      @Observe('count')
      void countChanged(val) {
        print("Count has changed : ${count}");
      }

      MyTag() { // <- Use a simple constructor for created callback !!!
        print("HELLO THERE !")
      }

      factory MyTag.tag() => Element.tag('my-tag'); // <- If you want to create it programmatically use this

      connectedCallback() {
        super.connectedCallback(); // <- MUST BE CALLED !!!!
      }
    }

The Html template is just the usual `dom-module`  template **without** any JS code. `Link` tags will be automatically generated based on the `uses` attribute of the  `@PolymerRegister` annotation (BTW : this fixes
also the annoying *unused import* problem with `polymer-dart`, and also the IDE will help you adding the right import).
The `index.html` should preload `requirejs`, `webcomponents` polyfill and `polymer.html` (see the demo).

## Output

After complilation everything will be found in the bazel output folder, ready to be used


## TODO:

 - more polymer APIs
 - better convert to/from JS
 - annotations for properties (computed props, etc.)
 - support for mixins
 - ~~support for external element wrappers~~
 - ~~support for auto gen HTML imports~~
