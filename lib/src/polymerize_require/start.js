// This file is taken from https://pub.dartlang.org/packages/browser

// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.


(function () {



    // Bootstrap support for Dart scripts on the page as this script.
    if (navigator.userAgent.indexOf('(Dart)') === -1) {

        /**
         *
         */
        function loadScriptPromise(link, src, replace) {
            return new Promise(function (resolve, reject) {
                let s = document.createElement('script');
                s.src = src;
                s.onload = function () {
                    resolve(s);
                };

                s.onerror = function (e) {
                    reject({'script': s, 'event': e});
                };

                let parent = link.parentElement;
                if (!!replace) {
                    document.currentScript = s;
                    parent.replaceChild(s, link);
                } else {
                    parent.insertBefore(s, link);
                }
            });
        }

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
                    let scriptSrc = scripts[i].src + ".bootstrap.js";
                    let parent = scripts[i].parentNode;
                    // TODO(vsm): Find a solution for issue 8455 that works with more
                    // than one script.
                    //document.currentScript = script;

                    let dartScript = scripts[i];
                    let exec = (s) => loadScriptPromise(dartScript, s, scriptSrc === s);

                    let p = null;
                    [
                        'require.js',
                        'polymerize_require/require.js',
                        'require.map.js',
                        scriptSrc
                    ].forEach((s) => p = (!!p) ? p = p.then(exec(s)) : exec(s));


                    break;
                }
            }
        }
    }
})();
