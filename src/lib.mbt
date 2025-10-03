///|
pub(all) struct Request {
  method_ : HttpMethod
  path_params : Map[String, String]
  query : Array[(String, String)]
  fragment : String?
  headers : Map[String, String]
  body : Bytes
}

///|
pub(all) struct Response {
  status_code : Int
  headers : Map[String, String]
  mut body : Bytes
}

///|
enum HttpMethod {
  String(String)
  // TODO: not supported now
  All
} derive(Eq, Show, Hash)

///|
typealias (Request, Response) -> Unit as HttpHandler

///|
struct HttpServer {
  routers : @hashmap.HashMap[
    HttpMethod,
    @sw_router.Router[
      ((Map[String, String], Array[(String, String)], String?), HttpHandler),
    ],
  ]
  mut socket : @sw_socket.Socket?
}

///|
/// (method, path, handler)
typealias (String, String, HttpHandler) as RouteConfig

///|
fn HttpServer::method_(
  self : HttpServer,
  method_ : String,
  path : String,
  handler : HttpHandler
) -> Unit raise @sw_router.AddRouteError {
  let http_method = match method_.to_upper() {
    "ALL" => HttpMethod::All
    "" => HttpMethod::All
    m => HttpMethod::String(m)
  }
  let router = self.routers.get_or_init(http_method, fn() {
    (try? {@sw_router.router([])}).unwrap()
  })
  router.add_route(path, fn(path_params, query, fragment) {
    ((path_params, query, fragment), handler)
  })
}

///|
pub fn new(
  routes : Array[RouteConfig],
) -> HttpServer raise @sw_router.AddRouteError {
  let server = HttpServer::{ routers: @hashmap.new(), socket: None }
  for route in routes {
    let (http_method, path, handler) = route
    server.method_(http_method, path, handler)
  }
  server
}

///|
pub fn HttpServer::listen(
  self : HttpServer,
  host : String,
  port : UInt16,
) -> Unit raise Failure {
  if not(self.socket.is_empty()) {
    fail("Server is already listening")
  }
  let server_socket = @sw_socket.new_socket(AF_INET, SOCK_STREAM)
  let _ = server_socket.bind(host, port)
  server_socket.listen(4096)
  self.socket = Some(server_socket)
}

///|
pub fn HttpServer::close(self : HttpServer) -> Unit raise {
  if self.socket.is_empty() {
    fail("Server is not listening")
  }
  let socket = self.socket.unwrap()
  socket.close()
  self.socket = None
}

///|
fn HttpServer::dispatch(
  self : HttpServer,
  method_ : HttpMethod,
  location : String,
  headers : Map[String, String],
  body : Bytes,
) -> Response raise {
  let router = self.routers.get(method_)
  if router.is_empty() {
    fail("No route found for method \{method_} and path \{location}")
  }
  // DispatchError::RouteNotMatched handle 404
  // ((path_params, query, fragment), handler)
  let route = router.unwrap().dispatch(location)
  let ((path_params, query, fragment), handler) = route
  let request = Request::{
    method_,
    path_params,
    query,
    fragment,
    headers,
    body,
  }
  let response = Response::{
    status_code: 200,
    headers: Map::new(),
    body: Bytes::default(),
  }
  handler(request, response)
  response
}

///|
pub fn HttpServer::poll(self : HttpServer) -> Unit raise {
  if self.socket.is_empty() {
    fail("Server is not listening")
  }
  let socket = self.socket.unwrap()
  let (client_socket, _) = socket.accept()
  let one_byte_read_buf : FixedArray[Byte] = FixedArray::make(1, (0).to_byte())
  let req_parser = HttpRequestParser::new()
  let buffer = @buffer.new(size_hint=4096)
  let mut is_parsing_header = true
  while true {
    if not(is_parsing_header) {
      break
    }
    let byte_received = client_socket.recv_buffer(one_byte_read_buf)
    if byte_received == 0 {
      break
    }
    for i in 0..<byte_received.to_int() {
      let byte = one_byte_read_buf[i]
      if req_parser.parse(byte) {
        is_parsing_header = false
      }
    }
  }
  // Content-Length
  // TODO: error handling
  let content_length = @strconv.parse_int64(
    req_parser.headers.get("Content-Length").unwrap_or("0"),
  )
  let content_remaining = content_length - buffer.length().to_int64()
  if content_remaining > 0 {
    let mut remaining = content_remaining
    while remaining > 0 {
      let byte_received = client_socket.recv_buffer(one_byte_read_buf)
      if byte_received == 0 {
        break
      }
      for i in 0..<byte_received.to_int() {
        let byte = one_byte_read_buf[i]
        buffer.write_byte(byte)
        remaining = remaining - 1
      }
    }
  }
  let bytes = buffer.to_bytes()
  let http_method = req_parser.http_method.unwrap()
  let http_method = HttpMethod::String(http_method.to_upper())
  let path = req_parser.location.unwrap()
  let response = self.dispatch(http_method, path, req_parser.headers, bytes)
  response.headers["Content-Length"] = response.body.length().to_string()
  let response_buffer = @buffer.new(size_hint=4096)
  response_buffer.write_bytes(
    @encoding.encode("HTTP/1.1 \{response.status_code} OK\r\n", encoding=UTF8),
  )
  response.headers.each(fn(k, v) {
    response_buffer.write_bytes(
      @encoding.encode("\{k}: \{v}\r\n", encoding=UTF8),
    )
  })
  response_buffer.write_bytes(@encoding.encode("\r\n", encoding=UTF8))
  response_buffer.write_bytes(response.body)
  let response_bytes = response_buffer.to_bytes()
  let _ = client_socket.send(response_bytes)
  client_socket.close()
}

///|
pub fn HttpServer::serve_forever(self : HttpServer) -> Unit {
  while true {
    (try? self.poll()).map_err(fn(e) {
      println("Error: \{e}")
      e
    })
    |> ignore
  }
}

///|
pub fn HttpServer::all(
  self : HttpServer,
  path : String,
  handler : HttpHandler,
) -> Unit raise @sw_router.AddRouteError {
  self.method_("ALL", path, handler)
}

///|
pub fn HttpServer::delete(
  self : HttpServer,
  path : String,
  handler : HttpHandler,
) -> Unit raise @sw_router.AddRouteError {
  self.method_("DELETE", path, handler)
}

///|
pub fn HttpServer::get(
  self : HttpServer,
  path : String,
  handler : HttpHandler,
) -> Unit raise @sw_router.AddRouteError {
  self.method_("GET", path, handler)
}

///|
pub fn HttpServer::head(
  self : HttpServer,
  path : String,
  handler : HttpHandler,
) -> Unit raise @sw_router.AddRouteError {
  self.method_("HEAD", path, handler)
}

///|
pub fn HttpServer::post(
  self : HttpServer,
  path : String,
  handler : HttpHandler,
) -> Unit raise @sw_router.AddRouteError {
  self.method_("POST", path, handler)
}

///|
pub fn HttpServer::put(
  self : HttpServer,
  path : String,
  handler : HttpHandler,
) -> Unit raise @sw_router.AddRouteError {
  self.method_("PUT", path, handler)
}

///|
pub fn HttpServer::connect(
  self : HttpServer,
  path : String,
  handler : HttpHandler,
) -> Unit raise @sw_router.AddRouteError {
  self.method_("CONNECT", path, handler)
}

///|
pub fn HttpServer::options(
  self : HttpServer,
  path : String,
  handler : HttpHandler,
) -> Unit raise @sw_router.AddRouteError {
  self.method_("OPTIONS", path, handler)
}

///|
pub fn HttpServer::trace(
  self : HttpServer,
  path : String,
  handler : HttpHandler,
) -> Unit raise @sw_router.AddRouteError {
  self.method_("TRACE", path, handler)
}

///|
pub fn HttpServer::copy(
  self : HttpServer,
  path : String,
  handler : HttpHandler,
) -> Unit raise @sw_router.AddRouteError {
  self.method_("COPY", path, handler)
}

///|
pub fn HttpServer::lock(
  self : HttpServer,
  path : String,
  handler : HttpHandler,
) -> Unit raise @sw_router.AddRouteError {
  self.method_("LOCK", path, handler)
}

///|
pub fn HttpServer::mkcol(
  self : HttpServer,
  path : String,
  handler : HttpHandler,
) -> Unit raise @sw_router.AddRouteError {
  self.method_("MKCOL", path, handler)
}

///|
pub fn HttpServer::move_(
  self : HttpServer,
  path : String,
  handler : HttpHandler,
) -> Unit raise @sw_router.AddRouteError {
  self.method_("MOVE", path, handler)
}

///|
pub fn HttpServer::propfind(
  self : HttpServer,
  path : String,
  handler : HttpHandler,
) -> Unit raise @sw_router.AddRouteError {
  self.method_("PROPFIND", path, handler)
}

///|
pub fn HttpServer::proppatch(
  self : HttpServer,
  path : String,
  handler : HttpHandler,
) -> Unit raise @sw_router.AddRouteError {
  self.method_("PROPPATCH", path, handler)
}

///|
pub fn HttpServer::search(
  self : HttpServer,
  path : String,
  handler : HttpHandler,
) -> Unit raise @sw_router.AddRouteError {
  self.method_("SEARCH", path, handler)
}

///|
pub fn HttpServer::unlock(
  self : HttpServer,
  path : String,
  handler : HttpHandler,
) -> Unit raise @sw_router.AddRouteError {
  self.method_("UNLOCK", path, handler)
}

///|
pub fn HttpServer::report(
  self : HttpServer,
  path : String,
  handler : HttpHandler,
) -> Unit raise @sw_router.AddRouteError {
  self.method_("REPORT", path, handler)
}

///|
pub fn HttpServer::mkactivity(
  self : HttpServer,
  path : String,
  handler : HttpHandler,
) -> Unit raise @sw_router.AddRouteError {
  self.method_("MKACTIVITY", path, handler)
}

///|
pub fn HttpServer::checkout(
  self : HttpServer,
  path : String,
  handler : HttpHandler,
) -> Unit raise @sw_router.AddRouteError {
  self.method_("CHECKOUT", path, handler)
}

///|
pub fn HttpServer::merge(
  self : HttpServer,
  path : String,
  handler : HttpHandler,
) -> Unit raise @sw_router.AddRouteError {
  self.method_("MERGE", path, handler)
}

///|
pub fn HttpServer::msearch(
  self : HttpServer,
  path : String,
  handler : HttpHandler,
) -> Unit raise @sw_router.AddRouteError {
  self.method_("M-SEARCH", path, handler)
}

///|
pub fn HttpServer::notify(
  self : HttpServer,
  path : String,
  handler : HttpHandler,
) -> Unit raise @sw_router.AddRouteError {
  self.method_("NOTIFY", path, handler)
}

///|
pub fn HttpServer::subscribe(
  self : HttpServer,
  path : String,
  handler : HttpHandler,
) -> Unit raise @sw_router.AddRouteError {
  self.method_("SUBSCRIBE", path, handler)
}

///|
pub fn HttpServer::unsubscribe(
  self : HttpServer,
  path : String,
  handler : HttpHandler,
) -> Unit raise @sw_router.AddRouteError {
  self.method_("UNSUBSCRIBE", path, handler)
}

///|
pub fn HttpServer::patch(
  self : HttpServer,
  path : String,
  handler : HttpHandler,
) -> Unit raise @sw_router.AddRouteError {
  self.method_("PATCH", path, handler)
}

///|
pub fn HttpServer::purge(
  self : HttpServer,
  path : String,
  handler : HttpHandler,
) -> Unit raise @sw_router.AddRouteError {
  self.method_("PURGE", path, handler)
}
