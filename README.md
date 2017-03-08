# Polymerize - Polymer 2.0 Dart-DDC

[![Join the chat at https://gitter.im/devc_builder/Lobby](https://badges.gitter.im/devc_builder/Lobby.svg)](https://gitter.im/devc_builder/Lobby?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

This package is a community effort to bring support for **Polymer 2** and latest HTML standards to Dart (DDC).

It features :
 - support for `polymer 2.0.0-rc.2` (web components 1.0)
 - using DDC to generate `ES6` output code
 - leverages [html5](https://github.com/dart-polymer/html5), a new html lib for Dart based on js interoperability only,
 - using [bazel](http://bazel.io) as build system (see also [rules](https://github.com/dart-polymer/bazel_polymerize_rules) )
 - **dynamic load** of polymer components definitions through `imd` (require js implementation using html imports)
 - **interoperability** with other JS frameworks
 - **Incremental** build (dependencies are built only once, thanks to DDC modularity system and bazel build)
 - possibility to distribute **ONLY** the build result to thirdy party users and devs
 - simplified API
   - automatic getter and setter (no explicit notify for first level properties)
   - **NO** Annotations required to expose properties
   - **NO** Annotations required to expose methods
 - seamless integration with widely used js tools like `bower`

## Disclaimer

`Polymerize` works on every platforms where `DDC` and `Bazel` runs that's MacOS and Linux for now.

### Browser compatibility

`Polymerize` uses `DDC` and `Polymer-2`, this means that it will only work on modern browsers. So far only `chrome` and `firefox` have been tested but `Safari` should work too along with latest IE11 builds.

Eventually some "transpiling" support can be added along with some optimizing post processing (like vulcanize or similar) could be added to the build chain to broaden the compatibility range.  

### Dazel

`Polymerize` doesn't uses `dazel` for now because it still lacks some feature that are needed for it to work, but the plan is to migrate to `dazel` as soon as it will be ready.

## Installation & usage

Polymerize can be intalled from pub :

    pub global activate polymerize

### Prepare a project

In order to build a project must be *prepared* for `polymerize`, just issue the following commands:

 1. `pub get/update` to check and resolve the dependencies (like in normal dart projects)
 2. `polymerize init` this will generate or update `bazel` build files

 This steps should be repeated every time the dependencies are changed.

### Build a project

 3. `bazel build default` this is the actual build

As *Bazel* is very fast and runs only on changed files you can make it automatically build the project every time a files changed with :

    `watch "bazel build default"`

# Developing with polymerize

## Sample project

A sample project illustrating how to build `polymer-2` components using `polymerize` can be found here :
 - [Sample mini todo APP for Polymer2-Dart-DDC Project](https://github.com/dam0vm3nt/todo_ddc)

See the [README](https://github.com/dam0vm3nt/polymer_dcc/blob/master/README.md) for more information.

## Component definition

This is a sample component definition:

    import 'package:polymer_element/polymer_element.dart';
    import 'package:my_component/other_component.dart' show OtherComponent;

    @PolymerRegister('my-tag',template:'my-tag.html',uses=[OtherComponent])
    abstract class MyTag extends PolymerElement {

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
        super.connectedCallback(); // <- super MUST BE CALLED if you override this callback (needed by webcomponents v1) !!!!
      }
    }

The Html template is just the usual `dom-module`  template **without** any JS code. The import dependencies will generate the appropriate html imports so there is no need to add them to
the template. The `uses` attribute of the  `@PolymerRegister` annotation is still there only for cosmetic reasons (this avoids
the annoying *unused import* analyzer warning when a component is imported but referenced only in the html template and not in the dart code, and also the IDE will help you adding the right import).

The `index.html` should preload `imd`, `webcomponents` polyfill and `polymer.html` (see the demo).

## Importing a Bower component

To import a bower component and use it in your project simply create a stub (that can created automatically, see below) for it and use the `@BowerImport` annotation along with `@PolymerRegister` with `native=true`, for instance:

    @PolymerRegister('paper-button',native:true)
    @BowerImport(ref:'PolymerElements/paper-button#2.0-preview',import:"paper-button/paper-button.html",name:'paper-button')
    abstract class PaperButton extends PolymerElement implements imp0.PaperButtonBehavior {
      /**
       * If true, the button should be styled with a shadow.
       */
      bool get raised;
      set raised(bool value);

    }

During the build phase `polymerize` will check any `@BowerImport` annotation on classes of dependencies, generate a `bower.json` file (using `resolutions` if you need to override something) and then
runs `bower install`.

You can also automatically generate a stub from the HTML `polymer` component using `polymerize generate_wrapper`, for instance:

    dart ../bin/polymerize.dart generate-wrapper --component-refs comps.yaml --dest-path out -p polymer_elements --bower-needs-map Polymer.IronFormElementBehavior=package:polymer_elements/iron_form_element_behavior.dart

The generator uses a yaml file describing the components to analyze passed through the `component-refs` options (see `gen/comps.yam` in this repo for an example).

The project [polymerize_elements](https://github.com/dam0vm3nt/polymerize_elements) is an example of wrappers generated using this tool for the `polymer-elements` components.

## Output

After complilation everything will be found in the bazel output folder (`bazel-bin`), ready to be used.

## TODO:

 - more polymer APIs
 - support for mixins
 - annotations for properties (computed props, etc.)
 - ~~support for external element wrappers~~
 - ~~support for auto gen HTML imports~~
 - `dazel` support
