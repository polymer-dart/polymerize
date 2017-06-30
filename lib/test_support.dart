@JS()
library polymerize_test_support;

import 'dart:js_util';
import 'package:js/js.dart';
import 'package:stream_channel/stream_channel.dart';
import "package:test/src/runner/plugin/remote_platform_helpers.dart";
import "package:test/src/utils.dart";
import 'package:html5/html.dart';

@JS()
@anonymous
class TestMessage {
  external String get href;
  external set href(String v);
  external get data;
  external set data(v);
  external get ready;
  external set ready(bool v);
  external factory TestMessage({String href,data,bool ready});
}

/// Constructs a [StreamChannel] wrapping `postMessage` communication with the
/// host page.
StreamChannel postMessageChannel() {
  var controller = new StreamChannelController(sync: true);

  new EventStreamProvider('message').forTarget(window).listen((message) {
    // A message on the Window can theoretically come from any website. It's
    // very unlikely that a malicious site would care about hacking someone's
    // unit tests, let alone be able to find the test server while it's
    // running, but it's good practice to check the origin anyway.
    if (message.origin != window.location.origin) return;
    message.stopPropagation();

    controller.local.sink.add(message.data);
  });

  Window parent = (window.parent as Window);

  controller.local.stream.listen((data) {
    // TODO(nweiz): Stop manually adding href here once issue 22554 is
    // fixed.
    TestMessage msg =new TestMessage(href:window.location.href, data:jsify(data));
    print('sending :${msg.href} / ${msg.data}');

    parent.postMessage(
        msg, window.location.origin);
  });

  // Send a ready message once we're listening so the host knows it's safe to
  // start sending events.
  print('sending ready');
  parent.postMessage(new TestMessage(href:window.location.href,ready:true), window.location.origin);

  return controller.foreign;
}


void runTest(AsyncFunction originalMain) {
  var channel = serializeSuite(() => originalMain);
  postMessageChannel().pipe(channel);
}