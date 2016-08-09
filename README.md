# Minimal build system for dev_compiler

This is a minimal build system to help people experiment with `dev_compiler`.

## Install

Install with `pub global activate devc_builder`.


## Usage

Launch the build with the following command:

    devc_builder main_package_path output_directory main_file_path

where

  -  `main_package_path` is the path to the main package to build
  -  `output_directory` guess what it is ?
  -  `main_file_path` is the relative path of the file (without the extension) inside the main package where your `main()` function resides

example:

    devc_builder my_app out index

will build the app inside `my_app` folder (that should be already "pub getted") in folder `out` using the file `my_app/lib/index.dart` as entry point.

## Output

This tool will transitively examine the main package dependencies and produce a single `js` module for each. All the `.dart` file inside any package
will be considered for compilation, all the other files copied to the output.

Compilation for `hosted` packages will be cached inside the folder `.repo` and reused for the next build.

Then it will create an `index.html` that will load all the dependencies and execute the `main` function in the `main_file_path`.

The `index.html` will be created with this template: 

```
<html>
<head>
<script>
'use strict';
</script>
@IMPORT_SCRIPTS@
@BOOTSTRAP@
</head>
<body>
</body>
</html>
```

You can provide your own template in `web/index.html`:

 - **@IMPORT_SCRIPTS@** will be replaced with all the import script from the dependencies and the SDK.
 - **@BOOTSTRAP@** will be replaced with the bootstrap code needed to execute the `main` function in the main file

You can test the results using a recent `chrome` or translate it with `babelJS`.

## TODO:

 - use args processing lib
 - execute `babelJS` / `vulcanize` / etc. etc.
 - try using `build` (can it be done ? how to handle group of sources?)
