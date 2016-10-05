# Poylmerize - Polymer 2.0 Dart experimental support

[![Join the chat at https://gitter.im/devc_builder/Lobby](https://badges.gitter.im/devc_builder/Lobby.svg)](https://gitter.im/devc_builder/Lobby?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

This package is a command line tool to build **Polymer 2** components with ** DDC ** from Dart.

The benefits of this approach compared to the `dart2js` standard `polymer-1.x` are :

 - support for `polymer 2.0-preview` (web components 1.0)
 - using DDC to generate `ES6` output code
 - **dynamic load** of polymer components definitions through `requirejs`
 - **interoperability** with other JS frameworks
 - **Incremental** build (dependencies are built only once)
 - possibility to distribute **ONLY** the build result to thirdy party users and devs
 - simplified API
   - automatic getter and setter (no explicit notify for first level properties)
   - **NO** Annotations required to expose properties
   - **NO** Annotations required to expose methods

## Disclaimer

Too good to be true ? Well the bad news is that although very promising this package is based on the **EXPERIMENTAL DEV COMPILER** and therefore this
is to be considered **HIGHLY UNSTABLE** and not ready for production.

Nevertheless it can be though as a POC to demostrate the extremely high potential of this approach for Dart.

This tool is tested *ONLY* on Linux. Should work on other unix based system. Probably will not work on windows.

## Install

Install with `pub global activate polymerize`.

## Usage

A sample project demostrating how to build `polymer-2` components using `polymerize` can be found here :
 - [https://github.com/dam0vm3nt/polymer_dcc](https://github.com/dam0vm3nt/polymer_dcc)

See the [README](https://github.com/dam0vm3nt/polymer_dcc/blob/master/README.md) for more information.

Launch the build with the following command:

 - `polymerize <main_package_directory> <output_directory>`

### Component definition

This is a sample component definition:

    import 'package:polymer_element/polymer_element.dart'

    @PolymerRegister('my-tag',template:'my-tag.html')
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

The Html template is just the usual `dom-module`  template **without** any JS code and with `<link>` to import other polymer dependencies (like polymer2 itself and
  any used component).
The `index.html` should preload `requirejs`, `webcomponents` polyfill and `polymer.html` (see the demo).

## Output

The build tool will operate in this way :

 - Every dependency of the main package will be processed and will produce a separate loadable module in the output Directory
 - For every polymer component a new `html` file will be produced that will load the original template and will load the corresponding dart class

Every file with ".dart" extension *inside* the `lib` folder of a dependency will be considered in the build of the corresponding module.

Every other file in the `lib` folder will be considered an `asset` and compied to the final build destination folder.

No other folder will be considered in the build. The only exception is the `web/index.html` file in the `main package` that must exist and is copied
to the final build destination folder.

Compilation for `hosted` packages will be cached inside the folder `.repo` (inside the current directory) and reused without rebuilding it for the next build.

## TODO:

 - more polymer APIs
 - better convert to/from JS
 - annotations for properties (computed props, etc.)
 - support for mixins
 - support for external element wrappers
 - support for auto gen HTML imports
