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

/**
 * A `Dispatcher` is used to customize the responses of the `MockWebServer`
 * further than using a queue.
 *
 * Using the `Dispatcher` will invalidate all the default response values
 * of the `MockWebServer` so be sure to set an `httpCode`.
 *
 * It is called with an `HttpRequest` object every time the `MockWebServer`
 * receives a request.
 *
 *   var dispatcher = (HttpRequest request) {
 *      if (request.uri.path == "/users") {
 *          return new MockResponse()
 *          ..httpCode = 200
 *          ..body = "working";
 *      } else if (request.uri.path == "/users/1") {
 *          return new MockResponse()..httpCode = 201;
 *      }
 *
 *      return new MockResponse()..httpCode = 404;
 *   };
 *
 *  _server.dispatcher = dispatcher;
 *
 */
typedef MockResponse Dispatcher(HttpRequest request);

/**
 * Defines a set of values that the `MockWebServer` will return to a given
 * request. Used with `MockWebServer.enqueueResponse(MockResponse response)` or
 * a `Dispatcher`.
 */
class MockResponse {
  Object body;
  int httpCode;
  Map<String, String> headers;
  Duration delay;
}

/**
 * A Web Server that can be scripted. Useful for Integration Tests, for demos,
 * and to reproduce edge cases.
 *
 *    _server = new MockWebServer();
 *    _server.start();
 *
 *    _server.enqueue(body: "Hello World", httpCode: 200);
 *
 * The simplest way of using the `MockWebServer` is to script the session with a
 * Queue. You can use `enqueue` and `enqueueResponse` for that. For a demo, a
 * tests with parallel requests, and other complicated scenarios than can't be
 * easily represented with just a queue, use a `Dispatcher`.
 */
class MockWebServer {
  /**
   * If the server has been started, returns the port in which the server
   * is running. If the server hasn't been started it will return the port
   * in which the server was requested to start, or zero if it wasn't requested
   * to start in an specific port.
   */
  int port;

  /**
   * Returns the host of the server. If there is no host associated with the
   * address, the IP will be returned here.
   *
   * Will be null if the server hasn't started.
   */
  String host;

  /**
   * Returns a String with the complete url to connect to the server. Will
   * be null if the server hasn't started.
   */
  String url;

  /**
   * Set this if using the queue is not enough for your requirements.
   */
  Dispatcher dispatcher;

  HttpServer _server;
  List<MockResponse> _responses = [];
  List<HttpRequest> _requests = [];

  /**
   * Creates an instance of a `MockWebServer`. If a [port] is defined, it
   * will be used when `start` is called. Otherwise, or if [:0:]
   * is passed as [port], the server will start in an ephemeral port picked
   * by the system.
   */
  MockWebServer({this.port: 0});

  /**
   * Starts the server. If a `port` was passed when the instance was created,
   * it will try to bind to that `port`, otherwise it will pick any available
   * port.
   */
  start() async {
    _server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, port);
    port = _server.port;
    host = _server.address.host;
    url = "http://$host:$port/";
    _serve();
  }

  /**
   * Creates a `MockResponse` with the passed parameters, and adds it to the
   * queue. The queue is First In First Out (FIFO).
   */
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

  /**
   * Adds the received `MockResponse` to the queue of responses of the server.
   * The queue is FIFO.
   */
  enqueueResponse(MockResponse response) {
    _responses.add(response);
  }

  /**
   * Returns the most recent request that was received by the server. Will
   * throw an exception if there aren't any requests available.
   */
  HttpRequest takeRequest() {
    if (_requests.isEmpty) {
      throw new Exception("No requests on record");
    }
    var request = _requests[_requests.length - 1];
    _requests.removeLast();

    return request;
  }

  /**
   * Start to listen for and process requests
   */
  _serve() async {
    await for (HttpRequest request in _server) {
      _requests.add(request);

      if (dispatcher != null) {
        assert(dispatcher is Dispatcher);
        MockResponse response = dispatcher(request);
        _process(request, response);
        continue;
      }

      if (_responses.isEmpty) {
        throw new Exception("No responses in queue");
      }

      var response = _responses[0];
      _responses.removeAt(0);

      _process(request, response);
    }
  }

  /**
   * Take the [response] and write its values to the [request], effectively
   * returning the response to the client.
   */
  _process(HttpRequest request, MockResponse response) async {
    if (response.delay != null) {
      Completer completer = new Completer();

      new Timer(response.delay, () {
        completer.complete();
      });

      await completer.future;
    }

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

  /**
   * Stop the `MockWebServer`
   */
  shutdown() {
    _server.close();
  }
}
