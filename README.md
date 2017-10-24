# MockWebServer
![build status](https://gitlab.com/Starcarr/MockWebServer/badges/master/build.svg)

A flexible Dart web server that can be used to script tests and web server interactions

## Summary

The best way to do integration tests, or to reproduce specific edge cases, is to
be able to script the interaction between the software that is being tested and the
web server.

MockWebServer aims to facility testing by offering a flexible stand alone
Server that will respond with a given script (or forward the request to your dispatcher).

MockWebServer is based on the 
[library](https://github.com/square/okhttp/tree/master/mockwebserver) 
of the same name created by Square for Java.

## Usage

### Starting it
MockWebServer can run in a given port or an ephemeral one
```dart
new MockWebServer(); // Will use an ephemeral port picked by the system
new MockWebServer(port: 8081); // Will use 8081
```

To start it just do
```dart
MockWebServer server = new MockWebServer();
server.start();
```

Once you have the server running you will want to get the url of it, so that you can
configure your app to connect there

```dart
server.url; // will return http://127.0.0.1:8081
server.port; // 8081
server.host; // 127.0.0.1
```

### Adding responses to the queue
Once the server is started, you can queue the responses that you want. **The response queue is 
First In First Out**

```dart
// Enqueue an empty body with response code 401
server.enqueue(httpCode: 401);

// Response code defaults to 200, so this will be a 200 with the given json as the body
server.enqueue(body: '{ "message" : "hi"}');

// HTTP 200 with empty body and some header
Map<String, String> headers = new Map();
headers["X-Server"] = "MockDart";
server.enqueue(headers: headers);

// All the parameters are optional so you can mix and match according to what you need
server.enqueue(httpCode: 201, body: "answer", headers: headers, duration: duration);

// You can always call enqueueResponse() to directly enqueue a MockResponse
Map<String, String> headers = new Map();
headers["X-Server"] = "MockDart";

var mockResponse = new MockResponse()
  ..httpCode = 201
  ..body = "Created"
  ..headers = headers
  ..delay = new Duration(seconds: 2);

server.enqueueResponse(mockResponse);
```

### Delaying the response
To test timeouts or race conditions you may want to have the server take some time

```dart
server.enqueue(delay: new Duration(seconds: 2), httpCode: 201);
Stopwatch stopwatch = new Stopwatch();
stopwatch.start();

HttpClientResponse response = request(path: "");

stopwatch.stop();
expect(stopwatch.elapsed.inMilliseconds, greaterThanOrEqualTo(2000));
expect(response.statusCode, 201);
```

### Validating that the request was correct
You may want to check that your app is sending the correct requests. To do so you can obtain the
requests that have been made to the server. **The request queue is Last In First Out**

```dart
server.enqueue(body: "a");
server.enqueue(body: "b");
server.enqueue(body: "c");

request(path: "first");
request(path: "second");
request(path: "third");

// takeRequest is LIFO
// You should probably assign takeRequest() to a var so that you can 
// validate multiple things.
expect(server.takeRequest().uri.path, "/third");
expect(server.takeRequest().method, "GET");
expect(server.takeRequest().headers['x-header'], "nosniff");
```

### Using a dispatcher for fine-grained routing

If you want more control than what the FIFO queue offers, you can set a dispatcher and set 
the logic there.

```dart
var dispatcher = (HttpRequest request) {
  if (request.uri.path == "/users") {
    return new MockResponse()
      ..httpCode = 200
      ..body = "working";
  } else if (request.uri.path == "/users/1") {
    return new MockResponse()..httpCode = 201;
  }

  return new MockResponse()..httpCode = 404;
};

server.dispatcher = dispatcher;

HttpClientResponse response = request(path: "unknown");
expect(response.statusCode, 404);

response = request(path: "users");
expect(response.statusCode, 200);
expect(read(response), "working");

response = request(path: "users/1");
expect(response.statusCode, 201);
```

### TLS
You can start the server using TLS by passing the `certificate` parameter 
when creating the instance of MockWebServer. For example using the included certificates and the
`resource` library you would do

```dart
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
    new MockWebServer(certificate: certificate);
```

If you do so, and your client validates the certs, you will need to use a
proper `SecurityContext`, for example using the included `trusted_certs.pem`

```dart
var certRes =
    new Resource('package:mock_web_server/certificates/trusted_certs.pem');
List<int> cert = await certRes.readAsBytes();

SecurityContext clientContext = new SecurityContext()
   ..setTrustedCertificatesBytes(cert);
    
var client = new HttpClient(context: clientContext);

```  

Please check the tests of MockWebServer to see a complete example of this.

### IPv6
If want to use IPv6, you can pass `addressType: InternetAddressType.IP_V6` in the 
constructor to have the server use it. Keep in mind that the `host` property 
will then be `::1` instead of `127.0.0.1`.  

```dart
MockWebServer _server =
        new MockWebServer(port: 8030, addressType: InternetAddressType.IP_V6);

```

### Stopping
During the `tearDown` of your tests you should stop the server. `server.shutdown()` will do.