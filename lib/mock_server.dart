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

import 'dart:io';
import 'dart:async';

class MockResponse {
  Object body;
  int httpCode;
  Map<String, String> headers;
  Duration delay;
}

class MockWebServer {
  int port;
  String host;
  String url;
  HttpServer _server;
  List<MockResponse> _responses = [];
  List<HttpRequest> _requests = [];
  var dispatcher;

  MockWebServer({this.port: 0});

  start() async {
    _server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, port);
    port = _server.port;
    host = _server.address.address;
    url = "http://$host:$port/";
    _serve();
  }

  enqueue(
      {Object body: "",
      int httpCode: 200,
      Map<String, String> headers,
      Duration delay}) {
    _responses.add(new MockResponse()
      ..body = body
      ..headers = headers
      ..httpCode = httpCode
      ..delay = delay);
  }

  enqueueResponse(MockResponse response) {
    _responses.add(response);
  }

  HttpRequest takeRequest() {
    if (_requests.isEmpty) {
      throw new Exception("No requests on record");
    }
    var request = _requests[_requests.length - 1];
    _requests.removeLast();

    return request;
  }

  void setDispatcher(MockResponse dispatcher(HttpRequest request)) {
    this.dispatcher = dispatcher;
  }

  _serve() async {
    await for (HttpRequest request in _server) {
      _requests.add(request);

      if (dispatcher != null) {
        MockResponse response = dispatcher(request);
        _execute(request, response);
        continue;
      }

      if (_responses.isEmpty) {
        throw new Exception("No responses in queue");
      }

      var response = _responses[0];
      _responses.removeAt(0);

      if (response.delay != null) {
        Completer completer = new Completer();

        await new Timer(response.delay, () {
          completer.complete();
        });

        await completer.future;
      }

      _execute(request, response);
    }
  }

  void _execute(HttpRequest request, MockResponse response) {
    if (response.headers != null) {
      response.headers.forEach((name, value) {
        request.response.headers.add(name, value);
      });
    }

    request.response
      ..statusCode = response.httpCode
      ..write(response.body)
      ..close();
  }

  shutdown() {
    _server.close();
  }
}
