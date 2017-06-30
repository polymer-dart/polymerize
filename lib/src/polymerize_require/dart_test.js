// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// This script runs in HTML files and loads the corresponding test scripts for
// either Dartium or a JS browser. It's used by "pub serve" and user-authored
// HTML files; when running without "pub serve", the default HTML file manually
// chooses between serving a Dart or JS script tag.
window.onload = function () {

    /**
     *
     */
    function loadScriptPromise(link, src, replace) {
        console.log('loading '+src);
        return new Promise(function (resolve, reject) {
            let s = document.createElement('script');
	    s.src=src;
            s.onload = function () {
                console.log('loaded '+src);
                resolve(s);
            };

            s.onerror = function (e) {
                reject({'script':s,'event':e});
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

// Sends an error message to the server indicating that the script failed to
// load.
//
// This mimics a MultiChannel-formatted message.
    var sendLoadException = function (message) {
        window.parent.postMessage({
            "href": window.location.href,
            "data": [0, {"type": "loadException", "message": message}]
        }, window.location.origin);
    }

    // Remove dangerous script
    //document.body.querySelector('script[src="packages/test/dart.js"]').remove();

// The basename of the current page.
    var name = window.location.href.replace(/.*\//, '').replace(/#.*/, '');

// Find <link rel="x-dart-test">.
    var links = document.getElementsByTagName("link");
    var testLinks = [];
    var length = links.length;
    for (var i = 0; i < length; ++i) {
        if (links[i].rel == "x-dart-test") testLinks.push(links[i]);
    }

    if (testLinks.length != 1) {
        sendLoadException(
            'Expected exactly 1 <link rel="x-dart-test"> in ' + name + ', found ' +
            testLinks.length + '.');
        return;
    }

    var link = testLinks[0];

    if (link.href == '') {
        sendLoadException(
            'Expected <link rel="x-dart-test"> in ' + name + ' to have an "href" ' +
            'attribute.');
        return;
    }


    // Load the compiled JS for a normal browser, and the Dart code for Dartium.
    if (navigator.userAgent.indexOf('(Dart)') !== -1) {
    }

    // Load scripts
    let ext = name.lastIndexOf('.html');
    let bootstrap = name.substring(0,ext)+'.dart.browser_test.dart.bootstrap.js';
    console.log('bootstrap name is '+bootstrap);

    let loading = loadScriptPromise(link,'require.js');

    loading = loading.then(function(){
        return loadScriptPromise(link,'polymerize_require/require.js')
    });

    loading = loading.then(function(){
        return loadScriptPromise(link,'require.map.js');
    });

    loading = loading.then(function(){
       return loadScriptPromise(link,bootstrap,true);
    });

    loading.catch(function(err){
        let message = "Failed to load script at " + err.script.src +
            (err.event.message ? ": " + err.event.message : ".");
        sendLoadException(message);
    });


};
