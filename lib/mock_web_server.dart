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

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

/// A `Dispatcher` is used to customize the responses of the `MockWebServer`
/// further than using a queue.
///
/// Using the `Dispatcher` will invalidate all the default response values
/// of the `MockWebServer` so be sure to set an `httpCode`.
///
/// It is called with an `HttpRequest` object every time the `MockWebServer`
/// receives a request.
///
///   var dispatcher = (HttpRequest request) {
///      if (request.uri.path == "/users") {
///          return new MockResponse()
///          ..httpCode = 200
///          ..body = "working";
///      } else if (request.uri.path == "/users/1") {
///          return new MockResponse()..httpCode = 201;
///      }
///
///      return new MockResponse()..httpCode = 404;
///   };
///
///  _server.dispatcher = dispatcher;
///
typedef Dispatcher = Future<MockResponse> Function(StoredRequest request);

/// Defines a set of values that the `MockWebServer` will return to a given
/// request. Used with `MockWebServer.enqueueResponse(MockResponse response)` or
/// a `Dispatcher`.
class MockResponse {
  Object body;
  int httpCode;
  Map<String, String> headers;
  Duration delay;
}

/// Contains the info of a request received by the MockWebServer instance.
class StoredRequest {
  String body;
  String method;
  Uri uri;
  Map<String, String> headers;
}

/// Represents a TLS certificate. `chain` and `key` are expected to be the bytes
/// of the file to not add any dependency on how to read the file.
class Certificate {
  List<int> chain;
  List<int> key;
  String password;
}

/// A Web Server that can be scripted. Useful for Integration Tests, for demos,
/// and to reproduce edge cases.
///
///    _server = new MockWebServer();
///    _server.start();
///
///    _server.enqueue(body: "Hello World", httpCode: 200);
///
/// The simplest way of using the `MockWebServer` is to script the session with
/// a Queue. You can use `enqueue` and `enqueueResponse` for that. For a demo, a
/// tests with parallel requests, and other complicated scenarios than can't be
/// easily represented with just a queue, use a `Dispatcher`.
class MockWebServer {
  /// Creates an instance of a `MockWebServer`. If a [port] is defined, it
  /// will be used when `start` is called. Otherwise, or if [:0:]
  /// is passed as [port], the server will start in an ephemeral port picked
  /// by the system.
  ///
  /// [https] defines whether the server will use TLS, if [https] is [:true:]
  /// you may want to use the trusted cert provided with the library in your
  /// [SecurityContext]. See
  /// [package:mock_web_server/certificates/trusted_certs.pem] or take a look at
  /// this project TLS tests to see a simple implementation.
  ///
  /// [addressType] allows you to decide if the Internet Address should be IPv4
  /// or IPv6. If [:IP_V4:] is used, then the address will be [:127.0.0.1:],
  /// if [:IP_V6] is used the address will be [:::1:]
  MockWebServer(
      {int port = 0,
      Certificate certificate,
      InternetAddressType addressType = InternetAddressType.IPv4}) {
    _port = port;
    if (certificate != null) {
      _https = true;
      _certificate = certificate;
    }
    _addressType = addressType;
  }

  /// If the server has been started, returns the port in which the server
  /// is running. Will throw [NoSuchMethodError] if the server is not started.
  int get port => _server.port;

  /// Returns the host of the server. [:127.0.0.1:] if the server is started
  /// with [:IPv4:], [:::1:] if it was started with [:IPv6:].
  /// Will throw [NoSuchMethodError] if the server is not started.
  String get host => _server.address.host;

  /// Returns a String with the complete url to connect to the server. Will
  /// throw [NoSuchMethodError] if the server is not started.
  String get url => "${_https ? "https" : "http"}://$host:$port/";

  /// Amount of requests that the server has received.
  int get requestCount => _requestCount;

  /// Set this if using the queue is not enough for your requirements.
  Dispatcher dispatcher;

  /// Default response if there's nothing on the queue and no dispatcher
  MockResponse defaultResponse;

  HttpServer _server;
  final Queue<MockResponse> _responses = Queue();
  final Queue<StoredRequest> _requests = Queue();
  int _port;
  bool _https = false;
  Certificate _certificate;
  InternetAddressType _addressType;
  int _requestCount = 0;

  /// Starts the server. If a `port` was passed when the instance was created,
  /// it will try to bind to that `port`, otherwise it will pick any available
  /// port.
  Future<void> start() async {
    final InternetAddress address = _addressType == InternetAddressType.IPv4
        ? InternetAddress.loopbackIPv4
        : InternetAddress.loopbackIPv6;

    if (_https) {
      final SecurityContext context = SecurityContext()
        ..useCertificateChainBytes(_certificate.chain)
        ..usePrivateKeyBytes(_certificate.key, password: _certificate.password);

      _server = await HttpServer.bindSecure(address, _port, context);
    } else {
      _server = await HttpServer.bind(address, _port);
    }

    _serve();
  }

  /// Creates a `MockResponse` with the passed parameters, and adds it to the
  /// queue. The queue is First In First Out (FIFO).
  void enqueue(
      {Object body = '',
      int httpCode = 200,
      Map<String, String> headers,
      Duration delay}) {
    _responses.add(MockResponse()
      ..body = body
      ..headers = headers
      ..httpCode = httpCode
      ..delay = delay);
  }

  /// Adds the received `MockResponse` to the queue of responses of the server.
  /// The queue is FIFO.
  void enqueueResponse(MockResponse response) {
    _responses.add(response);
  }

  /// Returns the requests received by the server, first in first out – FIFO.
  /// Will throw an exception if there aren't any requests available.
  StoredRequest takeRequest() {
    if (_requests.isEmpty) {
      throw Exception('No requests on record');
    }
    final request = _requests.first;
    _requests.removeFirst();

    return request;
  }

  /// Stop the `MockWebServer`
  void shutdown() {
    _server.close();
  }

  /// Start to listen for and process requests
  Future<void> _serve() async {
    await for (final HttpRequest request in _server) {
      _requestCount++;
      final storedRequest = await _toStoredRequest(request);
      _requests.add(storedRequest);

      if (dispatcher != null) {
        assert(dispatcher is Dispatcher);
        final MockResponse response = await dispatcher(storedRequest);
        _process(request, response);
        continue;
      }

      if (_responses.isEmpty && defaultResponse == null) {
        throw Exception('No responses in queue and no default response');
      }

      var response = defaultResponse;

      if (_responses.isNotEmpty) {
        response = _responses.first;
        _responses.removeFirst();
      }

      _process(request, response);
    }
  }

  /// Transform an [HttpRequest] into a [StoredRequest]
  Future<StoredRequest> _toStoredRequest(HttpRequest request) async {
    final Map<String, String> headers = {};

    final StringBuffer body = StringBuffer();
    final Completer<String> completer = Completer();

    utf8.decoder.bind(request).listen((data) {
      body.write(data);
    }, onDone: () {
      completer.complete(body.toString());
    });

    request.headers.forEach((key, values) {
      headers[key] = values.join(', ');
    });

    return StoredRequest()
      ..method = request.method
      ..headers = headers
      ..uri = request.uri
      ..body = await completer.future;
  }

  /// Take the [response] and write its values to the [request], effectively
  /// returning the response to the client.
  Future<void> _process(HttpRequest request, MockResponse response) async {
    if (response.delay != null) {
      final Completer completer = Completer<dynamic>();

      Timer(response.delay, () {
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
