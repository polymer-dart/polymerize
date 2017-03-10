import 'dart:async';

import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;

Future runPubMode(ArgResults params) async {
  // Ask pub to download
  var baseApiUrl = params['pub-host'] ?? "https://pub.dartlang.org/api";
  var url = "$baseApiUrl/packages/${params['package']}";
  HttpClient client = new HttpClient();
  HttpClientRequest req = await client.getUrl(Uri.parse(url));
  req.headers.contentType = new ContentType('application', 'json');
  HttpClientResponse response = await req.close();
  if (response.statusCode >= 300) {
    throw "error resp";
  }

  String body = await response.transform(UTF8.decoder).fold("", (a, b) => a + b);

  Map res = JSON.decode(body);

  Map ver = res['versions'].firstWhere((Map x) => x['version'] == params['version']);

  String archive_url = ver['archive_url'];

  print("RES: ${archive_url}");

  req = await client.getUrl(Uri.parse(archive_url));
  response = await req.close();
  List<int> allBytes = [];
  await response.transform(GZIP.decoder).forEach((x) => allBytes.addAll(x));

  Archive a = new TarDecoder().decodeBytes(allBytes);

  a.files.forEach((f) {
    new File(path.join(params['dest'], f.name))
      ..createSync(recursive: true)
      ..writeAsBytesSync(f.content);
  });

  client.close();
}
