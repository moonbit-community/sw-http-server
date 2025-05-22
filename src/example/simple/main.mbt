///|
fn wrapped_main() -> Unit! {
  let server = @sw_http_server.new!([])
  server.get!("/", fn(req, res) {
    let resp = StringBuilder::new()
    resp..write_string("Hello, World!\n\n")..write_string("Request Headers:\n")
    for key, value in req.headers.iter2() {
      resp
      ..write_string("  ")
      ..write_string(key)
      ..write_string(": ")
      ..write_string(value)
      ..write_string("\n")
    }
    resp
    ..write_string("Request Body:\n")
    ..write_string("  ")
    ..write_string(req.body.to_string())
    ..write_string("\n")
    ..write_string("Request Method: ")
    ..write_string(req.method_.to_string())
    ..write_string("\n")
    ..write_string("Query Parameters:\n")
    for _, kv in req.query.iter2() {
      let (key, value) = kv
      resp
      ..write_string("  ")
      ..write_string(key)
      ..write_string(": ")
      ..write_string(value)
      ..write_string("\n")
    }
    resp
    ..write_string("Fragment: ")
    ..write_string(req.fragment.to_string())
    ..write_string("\n")
    let resp_bytes = @encoding.encode(resp.to_string(), encoding=UTF8)
    res.headers.set("Content-Type", "text/plain")
    res.body = resp_bytes
  })
  server.listen!("0.0.0.0", 8080)
  server.serve_forever()
}

///|
fn main {
  wrapped_main?()
  .map_err(fn(e) {
    println("Error: \{e}")
    e
  })
  .unwrap()
}
