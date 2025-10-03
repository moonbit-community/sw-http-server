///|
fn wrapped_main() -> Unit raise {
  let server = @sw_http_server.new([])
  server.get("/", fn(req, res) {
    let resp: Json = {
      "message": "Hello, World!",
      "headers": req.headers,
      "body": req.body.to_string(),
      "method": req.method_.to_string(),
      "query": req.query,
      "fragment": req.fragment.to_string(),
    }
    let resp_bytes = @encoding.encode(resp.stringify(), encoding=UTF8)
    res.headers.set("Content-Type", "text/plain")
    res.body = resp_bytes
  })
  server.listen("0.0.0.0", 8082)
  server.serve_forever()
}

///|
fn main {
  (try? wrapped_main())
  .map_err(fn(e) {
    println("Error: \{e}")
    e
  })
  .unwrap()
}
