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

import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:collection';

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
typedef Future<MockResponse> Dispatcher(HttpRequest request);

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
 * Contains the info of a request received by the MockWebServer instance.
 */
class StoredRequest {
  String body;
  String method;
  Uri uri;
  Map<String, String> headers;
}

/**
 * Represents a TLS certificate. `chain` and `key` are expected to be the bytes
 * of the file to not add any dependency on how to read the file.
 */
class Certificate {
  List<int> chain;
  List<int> key;
  String password;
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
   * is running. Will throw [NoSuchMethodError] if the server is not started.
   */
  int get port => _server.port;

  /**
   * Returns the host of the server. [:127.0.0.1:] if the server is started
   * with [:IPv4:], [:::1:] if it was started with [:IPv6:].
   *
   * Will throw [NoSuchMethodError] if the server is not started.
   */
  String get host => _server.address.host;

  /**
   * Returns a String with the complete url to connect to the server. Will
   * throw [NoSuchMethodError] if the server is not started.
   */
  String get url => "${_https ? "https" : "http"}://$host:$port/";

  /**
   * Amount of requests that the server has received.
   */
  int get requestCount => _requestCount;

  /**
   * Set this if using the queue is not enough for your requirements.
   */
  Dispatcher dispatcher;

  HttpServer _server;
  Queue<MockResponse> _responses = new Queue();
  Queue<StoredRequest> _requests = new Queue();
  int _port;
  bool _https = false;
  Certificate _certificate;
  InternetAddressType _addressType;
  int _requestCount = 0;

  /**
   * Creates an instance of a `MockWebServer`. If a [port] is defined, it
   * will be used when `start` is called. Otherwise, or if [:0:]
   * is passed as [port], the server will start in an ephemeral port picked
   * by the system.
   *
   * [https] defines whether the server will use TLS, if [https] is [:true:]
   * you may want to use the trusted cert provided with the library in your
   * [SecurityContext]. See
   * [package:mock_web_server/certificates/trusted_certs.pem] or take a look at
   * this project TLS tests to see a simple implementation.
   *
   * [addressType] allows you to decide if the Internet Address should be IPv4 or
   * IPv6. If [:IP_V4:] is used, then the address will be [:127.0.0.1:], if [:IP_V6]
   * is used the address will be [:::1:]
   */
  MockWebServer(
      {port: 0,
      Certificate certificate,
      addressType: InternetAddressType.IP_V4}) {
    _port = port;
    if (certificate != null) {
      _https = true;
      _certificate = certificate;
    }
    _addressType = addressType;
  }

  /**
   * Starts the server. If a `port` was passed when the instance was created,
   * it will try to bind to that `port`, otherwise it will pick any available
   * port.
   */
  start() async {
    InternetAddress address = _addressType == InternetAddressType.IP_V4
        ? InternetAddress.LOOPBACK_IP_V4
        : InternetAddress.LOOPBACK_IP_V6;

    if (_https) {
      SecurityContext context = new SecurityContext()
        ..useCertificateChainBytes(_certificate.chain)
        ..usePrivateKeyBytes(_certificate.key, password: _certificate.password);

      _server = await HttpServer.bindSecure(address, _port, context);
    } else {
      _server = await HttpServer.bind(address, _port);
    }

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
  StoredRequest takeRequest() {
    if (_requests.isEmpty) {
      throw new Exception("No requests on record");
    }
    var request = _requests.last;
    _requests.removeLast();

    return request;
  }

  /**
   * Stop the `MockWebServer`
   */
  shutdown() {
    _server.close();
  }

  /**
   * Start to listen for and process requests
   */
  _serve() async {
    await for (HttpRequest request in _server) {
      _requestCount++;
      _requests.add(await _toStoredRequest(request));

      if (dispatcher != null) {
        assert(dispatcher is Dispatcher);
        MockResponse response = await dispatcher(request);
        _process(request, response);
        continue;
      }

      if (_responses.isEmpty) {
        throw new Exception("No responses in queue");
      }

      var response = _responses.first;
      _responses.removeFirst();

      _process(request, response);
    }
  }

  /**
   * Transform an [HttpRequest] into a [StoredRequest]
   */
  Future<StoredRequest> _toStoredRequest(HttpRequest request) async {
    Map<String, String> headers = new Map();

    StringBuffer body = new StringBuffer();
    Completer<String> completer = new Completer();

    request.transform(UTF8.decoder).listen((data) {
      body.write(data);
    }, onDone: () {
      completer.complete(body.toString());
    });

    request.headers.forEach((key, values) {
      headers[key] = values.join(", ");
    });

    return new StoredRequest()
      ..method = request.method
      ..headers = headers
      ..uri = request.uri
      ..body = await completer.future;
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
}
