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
  -  `main_file_path` is the relative path inside the main package where your `main()` function resides

## Output

This tool will transitively examine the main package dependencies and produce a single `js` module for each. 

Then it will create an `index.html` that will load all the dependencies and execute the `main` function in the `main_file_path`.

You can test the results using `chrome canary` or translate it with `babelJS` and use `chrome`. If simple enough recent `chrome` version 
can run it without any translations.

## TODO:

 - copying resources (at the moment it only translates .dart sources)
 - execute `babelJS` / `vulcanize` / etc. etc.
 - try using `build` (can it be done ? how to handle group of sources?)
