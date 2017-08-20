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

    expect(_server.takeRequest().uri.path, "/third");
    expect(_server.takeRequest().uri.path, "/second");
    expect(_server.takeRequest().uri.path, "/first");
    expect(_server.requestCount, 3);
  });

  test("Dispatcher", () async {
    var dispatcher = (HttpRequest request) {
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

  response.transform(UTF8.decoder).listen((data) {
    body.write(data);
  }, onDone: () {
    completer.complete(body.toString());
  });

  await completer.future;
  return body.toString();
}
