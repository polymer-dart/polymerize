// This file is taken from https://pub.dartlang.org/packages/browser

// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.


(function () {
// Bootstrap support for Dart scripts on the page as this script.
    if (navigator.userAgent.indexOf('(Dart)') === -1) {
        // TODO:
        // - Support in-browser compilation.
        // - Handle inline Dart scripts.

        // Fall back to compiled JS. Run through all the scripts and
        // replace them if they have a type that indicate that they source
        // in Dart code (type="application/dart").
        var scripts = document.getElementsByTagName("script");
        var length = scripts.length;
        for (var i = 0; i < length; ++i) {
            if (scripts[i].type == "application/dart") {
                // Remap foo.dart to foo.dart.js.
                if (scripts[i].src && scripts[i].src != '') {
                    let script = document.createElement('script');
                    script.src = scripts[i].src + ".bootstrap.js";
                    let parent = scripts[i].parentNode;
                    // TODO(vsm): Find a solution for issue 8455 that works with more
                    // than one script.
                    document.currentScript = script;

                    let dartScript = scripts[i];
                    // Add require and require map
                    let req = document.createElement('script');
                    req.src = 'require.js';
                    req.onload = function () {
                        let reqred = document.createElement('script');
                        reqred.src = 'polymerize_require/require.js';
                        parent.insertBefore(reqred, dartScript);
                        reqred.onload = function () {
                            // DEBUG : LOAD STACK TRACE MAPPER TOO
                            let stacktr = document.createElement('script');
                            stacktr.src = 'dart_stack_trace_mapper.js';
                            parent.insertBefore(stacktr, dartScript);
                            stacktr.onload = function () {
                                let reqmap = document.createElement('script');
                                reqmap.src = 'require.map.js';
                                parent.insertBefore(reqmap, dartScript);
                                reqmap.onload = function () {
                                    parent.replaceChild(script, dartScript);
                                };
                            };
                            /*};
                             fakereq.send();*/
                        };
                    };
                    parent.insertBefore(req, dartScript);


                    break;
                }
            }
        }
    }
})();
