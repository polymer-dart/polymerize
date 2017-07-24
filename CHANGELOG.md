# 0.9.5
 - fixes
 - better support for builders

# 0.9.4
 - added support for tests!!!

# 0.9.2
 - better detecting of bower
 - added support for dart stack trace mapping

# 0.9.1+1
 - fix for windows
# 0.9.1
 - require loading 

# 0.9.0
 - moving to pub+ddc

# 0.8.5
 - support for autonotify behavior

# 0.8.4
 - added support for behaviors on behaviors
 - restored native element class
 - better performance (analyzer context recycled)
 - one action to build'em all (build_and_generate)
 - redux is now a normal behavior/mixin
 
# 0.8.3
 - max workers set to 2
 - fixed behaviors generation

# 0.8.2
 - fixed bad bower dependency calc

# 0.8.1
 - rewritten to keep most things in dart 
 - changed bower strategy (now it is a workspace)
 - added support for bazel workers (still need some optimization)
 - support for latest polymer
 - using SDK ddc instead of extracted DDC package
 - changed module strategy : one file per module makes it possible to load only what is needed 

# 0.7.2

 - upgrade to SDK v. 1.23.0
 - support for dart property getters and setters
 
# 0.7.1+1
 
 - locked analyzer version until we upgrade DDC library (https://github.com/polymer-dart/todo_ddc/issues/5)

# 0.7.1

 - updated to DDC-2017031301
 - added option to override JS name in generated wrapper

# 0.7.0+1

 - fixed rules version

# 0.7.0

 - support for mixin in dart

# 0.6.1

 - better error handling during setup phase

# 0.6.0+2

 - minor changes to readme

# 0.6.0+1

 - minor change to rules

# 0.6.0

 - changed module name convention - please update `polymer_elements` and `html5` too

# 0.5.4

 - better error logging

# 0.5.3

 - added `bower_resolutions.yaml` optional ovverride for `polymerize init`

# 0.5.2

 - fixed bug on generator
 - support for embedded templates

# 0.5.1
 
 - changed urls and references

# 0.5.0

 - added support for mixins
 - better wrapper generation
 - updated polymer analyzer
 - support for REDUX!!!

# 0.4.5

 - update to latest DDC (dart 1.23-dev.x) - 2017 02 21

# 0.4.4

 - updated to latest DDC (dart 1.22-dev.x)

# 0.2.5
 - Updated libs
 
# 0.2.4
 - Added support for vanilla WebComponents
 - Fixed for `.packages` (dart 1.20)

# 0.2.3
 - Adding support for wrapping external elements (see `paper_dialog.dart`)
 - Adding support for dynamic load of dart packages
 - Adding support for **OBSERVABLE** proxy (see todo demo)
 - Cleanups and improvments

# 0.2.2
 - Rudimental support for custom events

# 0.2.1

 - changed name to `polymerize`
 - add commandline args
 - added no emit option (to build libraries apart)
 - copy all `web` assets (not only `index.html`)
 - added option for module format (even if ony `amd` is actually fully supported)
 - added centralized repository

## 0.1.2+1

 - reset options for compiler

## 0.1.2

 - repo for compilation
 - copying resources
 - templating
