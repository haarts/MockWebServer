/*
 * Copyright (C) 2017 Miguel Castiblanco
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'package:mock_web_server/mock_web_server.dart';
import 'package:test/test.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:resource/resource.dart' show Resource;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

MockWebServer _server;

void main() {
  setUp(() {
    _server = new MockWebServer();
    _server.start();
  });

  tearDown(() {
    _server.shutdown();
  });

  test("Set response code", () async {
    _server.enqueue(httpCode: 401);
    HttpClientResponse response = await _get("");
    expect(response.statusCode, 401);
  });

  test("Set body", () async {
    _server.enqueue(body: "something");
    HttpClientResponse response = await _get("");
    expect(await _read(response), "something");
  });

  test("Set headers", () async {
    Map<String, String> headers = new Map();
    headers["X-Server"] = "MockDart";

    _server.enqueue(body: "Created", httpCode: 201, headers: headers);
    HttpClientResponse response = await _get("");
    expect(response.statusCode, 201);
    expect(response.headers.value("X-Server"), "MockDart");
    expect(await _read(response), "Created");
  });

  test("Set body and response code", () async {
    _server.enqueue(body: "Created", httpCode: 201);
    HttpClientResponse response = await _get("");
    expect(response.statusCode, 201);
    expect(await _read(response), "Created");
  });

  test("Set body, response code, and headers", () async {
    Map<String, String> headers = new Map();
    headers["X-Server"] = "MockDart";

    _server.enqueue(body: "Created", httpCode: 201, headers: headers);
    HttpClientResponse response = await _get("");
    expect(response.statusCode, 201);
    expect(response.headers.value("X-Server"), "MockDart");
    expect(await _read(response), "Created");
  });

  test("Queue", () async {
    _server.enqueue(body: "hello");
    _server.enqueue(body: "world");
    HttpClientResponse response = await _get("");
    expect(await _read(response), "hello");

    response = await _get("");
    expect(await _read(response), "world");
  });

  test("Take requests & request count", () async {
    _server.enqueue(body: "a");
    _server.enqueue(body: "b");
    _server.enqueue(body: "c");
    await _get("first");
    await _get("second");
    await _get("third");

    expect(_server.takeRequest().uri.path, "/first");
    expect(_server.takeRequest().uri.path, "/second");
    expect(_server.takeRequest().uri.path, "/third");
    expect(_server.requestCount, 3);
  });

  test("Request count", () async {
    _server.enqueue(httpCode: HttpStatus.unauthorized);

    await _get("first");

    expect(_server.takeRequest().uri.path, "/first");
    expect(_server.requestCount, 1);
  });

  test("Dispatcher", () async {
    var dispatcher = (HttpRequest request) async {
      if (request.uri.path == "/users") {
        return new MockResponse()
          ..httpCode = 200
          ..body = "working";
      } else if (request.uri.path == "/users/1") {
        return new MockResponse()..httpCode = 201;
      } else if (request.uri.path == "/delay") {
        return new MockResponse()
          ..httpCode = 200
          ..delay = new Duration(milliseconds: 1500);
      }

      return new MockResponse()..httpCode = 404;
    };

    _server.dispatcher = dispatcher;

    HttpClientResponse response = await _get("unknown");
    expect(response.statusCode, 404);

    response = await _get("users");
    expect(response.statusCode, 200);
    expect(await _read(response), "working");

    response = await _get("users/1");
    expect(response.statusCode, 201);

    Stopwatch stopwatch = new Stopwatch()..start();
    response = await _get("delay");
    stopwatch.stop();
    expect(stopwatch.elapsed.inMilliseconds,
        greaterThanOrEqualTo(new Duration(milliseconds: 1500).inMilliseconds));
    expect(response.statusCode, 200);
  });

  test("Enqueue MockResponse", () async {
    Map<String, String> headers = new Map();
    headers["X-Server"] = "MockDart";

    var mockResponse = new MockResponse()
      ..httpCode = 201
      ..body = "Created"
      ..headers = headers;

    _server.enqueueResponse(mockResponse);
    HttpClientResponse response = await _get("");
    expect(response.statusCode, 201);
    expect(response.headers.value("X-Server"), "MockDart");
    expect(await _read(response), "Created");
  });

  test("Delay", () async {
    _server.enqueue(delay: new Duration(seconds: 2), httpCode: 201);
    Stopwatch stopwatch = new Stopwatch()..start();
    HttpClientResponse response = await _get("");

    stopwatch.stop();
    expect(stopwatch.elapsed.inMilliseconds,
        greaterThanOrEqualTo(new Duration(seconds: 2).inMilliseconds));
    expect(response.statusCode, 201);
  });

  test('Parallel delay', () async {
    String body70 = "70 milliseconds";
    String body40 = "40 milliseconds";
    String body20 = "20 milliseconds";
    _server.enqueue(delay: new Duration(milliseconds: 40), body: body40);
    _server.enqueue(delay: new Duration(milliseconds: 70), body: body70);
    _server.enqueue(delay: new Duration(milliseconds: 20), body: body20);

    Completer completer = new Completer();
    List<String> responses = new List();

    _get("").then((res) async {
      // 40 milliseconds
      String result = await _read(res);
      responses.add(result);
    });

    _get("").then((res) async {
      // 70 milliseconds
      String result = await _read(res);
      responses.add(result);

      // complete on the longer operation
      completer.complete();
    });

    _get("").then((res) async {
      // 20 milliseconds
      String result = await _read(res);
      responses.add(result);
    });

    await completer.future;

    // validate that the responses happened in order 20, 40, 70
    expect(responses[0], body20);
    expect(responses[1], body40);
    expect(responses[2], body70);
  });

  test("Request specific port IPv4", () async {
    MockWebServer _server = new MockWebServer(port: 8029);
    await _server.start();

    RegExp url = new RegExp(r'(?:http[s]?:\/\/(?:127\.0\.0\.1):8029\/)');
    RegExp host = new RegExp(r'(?:127\.0\.0\.1)');

    expect(url.hasMatch(_server.url), true);
    expect(host.hasMatch(_server.host), true);
    expect(_server.port, 8029);

    _server.shutdown();
  });

  test("Request specific port IPv6", () async {
    MockWebServer _server =
        new MockWebServer(port: 8030, addressType: InternetAddressType.IPv6);
    await _server.start();

    RegExp url = new RegExp(r'(?:http[s]?:\/\/(?:::1):8030\/)');
    RegExp host = new RegExp(r'(?:::1)');

    expect(url.hasMatch(_server.url), true);
    expect(host.hasMatch(_server.host), true);
    expect(_server.port, 8030);

    _server.shutdown();
  });

  test("TLS info", () async {
    var chainRes =
        new Resource('package:mock_web_server/certificates/server_chain.pem');
    List<int> chain = await chainRes.readAsBytes();

    var keyRes =
        new Resource('package:mock_web_server/certificates/server_key.pem');
    List<int> key = await keyRes.readAsBytes();

    Certificate certificate = new Certificate()
      ..password = "dartdart"
      ..key = key
      ..chain = chain;

    MockWebServer _server =
        new MockWebServer(port: 8029, certificate: certificate);
    await _server.start();

    RegExp url = new RegExp(r'(?:https:\/\/(?:127\.0\.0\.1):8029\/)');
    RegExp host = new RegExp(r'(?:127\.0\.0\.1)');

    expect(url.hasMatch(_server.url), true);
    expect(host.hasMatch(_server.host), true);
    expect(_server.port, 8029);

    _server.shutdown();
  });

  test("TLS cert", () async {
    String body = "S03E08 You Are Not Safe";

    var chainRes =
        new Resource('package:mock_web_server/certificates/server_chain.pem');
    List<int> chain = await chainRes.readAsBytes();

    var keyRes =
        new Resource('package:mock_web_server/certificates/server_key.pem');
    List<int> key = await keyRes.readAsBytes();

    Certificate certificate = new Certificate()
      ..password = "dartdart"
      ..key = key
      ..chain = chain;

    MockWebServer _server =
        new MockWebServer(port: 8029, certificate: certificate);
    await _server.start();
    _server.enqueue(body: body);

    var certRes =
        new Resource('package:mock_web_server/certificates/trusted_certs.pem');
    List<int> cert = await certRes.readAsBytes();

    // Calling without the proper security context
    var clientErr = new HttpClient();

    expect(clientErr.getUrl(Uri.parse(_server.url)),
        throwsA(new TypeMatcher<HandshakeException>()));

    // Testing with security context
    SecurityContext clientContext = new SecurityContext()
      ..setTrustedCertificatesBytes(cert);

    var client = new HttpClient(context: clientContext);
    var request = await client.getUrl(Uri.parse(_server.url));
    String response = await _read(await request.close());

    expect(response, body);

    _server.shutdown();
  });

  test("Check take request", () async {
    _server.enqueue();

    HttpClient client = new HttpClient();
    HttpClientRequest request =
        await client.post(_server.host, _server.port, "test");
    request.headers.add("x-header", "nosniff");
    request.write("sample body");

    await request.close();
    StoredRequest storedRequest = _server.takeRequest();

    expect(storedRequest.method, "POST");
    expect(storedRequest.body, "sample body");
    expect(storedRequest.uri.path, "/test");
    expect(storedRequest.headers['x-header'], "nosniff");
  });

  test("default response", () async {
    _server.defaultResponse = MockResponse()..httpCode = 404;

    var response = await _get("");
    expect(response.statusCode, 404);
  });

  group("WebSockets", () {
    String url;

    setUp(() {
      url = "ws://${_server.host}:${_server.port}/ws";
    });

    test("with single response", () async {
      _server.enqueue(body: "some response");

      final channel = IOWebSocketChannel.connect(url);
      channel.sink.add("initial message (mandatory)");
      channel.stream.listen(expectAsync1((message) {
        expect(message, equals("some response"));
      }));
    });

    test("with multiple responses", () async {
      _server.enqueue(body: "response 1");
      _server.enqueue(body: "response 2");

      // NOTE responses are popped from the end therefor this seems reversed.
      List<void Function(String)> expectations = [
        (message) => expect(message, equals("response 2")),
        (message) => expect(message, equals("response 1")),
      ];

      final channel = IOWebSocketChannel.connect(url);
      channel.sink.add("initial message (mandatory)");
      channel.stream.listen(expectAsync1((message) {
        expectations.removeLast()(message);
        if (expectations.length != 0) {
          channel.sink.add("next message please");
        }
      }, count: 2));
    });

    test("with delayed response", () async {
      _server.enqueue(
          body: "some response", delay: Duration(milliseconds: 1500));

      Stopwatch stopwatch = Stopwatch()..start();
      Completer c = Completer();

      final channel = IOWebSocketChannel.connect(url);
      channel.sink.add("initial message (mandatory)");
      channel.stream.listen(expectAsync1((message) {
        c.complete();
      }));
      await c.future;

      stopwatch.stop();
      expect(stopwatch.elapsed.inMilliseconds,
          greaterThanOrEqualTo(Duration(milliseconds: 1500).inMilliseconds));
    });

    test("with a message generator", () async {
         // FIXME potentionally add Stream argument, what about closeCode and closeReason
      _server.messageGenerator = (StreamSink sink) async {
          await Future.delayed(Duration(seconds: 1), () => sink.add("first"));
          await Future.delayed(Duration(seconds: 1), () => sink.add("second"));
          await Future.delayed(Duration(seconds: 1), () => sink.add("third"));
      };

      List<void Function(String)> expectations = [
        (message) => expect(message, equals("third")),
        (message) => expect(message, equals("second")),
        (message) => expect(message, equals("first")),
      ];

      final channel = IOWebSocketChannel.connect(url);
      channel.stream.listen(expectAsync1((message) {
        expectations.removeLast()(message);
      }, count: 3));
    });

    test("with close code", () async {}, skip: "TODO");
    test("with close reason", () async {}, skip: "TODO");
    test("with greeting", () async {}, skip: "TODO");
    test("with repeated connections", () async {}, skip: "TODO");
  });
}

_get(String path) async {
  HttpClient client = new HttpClient();
  HttpClientRequest request =
      await client.get(_server.host, _server.port, path);
  return await request.close();
}

Future<String> _read(HttpClientResponse response) async {
  StringBuffer body = new StringBuffer();
  Completer<String> completer = new Completer();

  response.transform(utf8.decoder).listen((data) {
    body.write(data);
  }, onDone: () {
    completer.complete(body.toString());
  });

  await completer.future;
  return body.toString();
}
