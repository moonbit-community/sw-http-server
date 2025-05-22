///|
priv enum HttpRequestParserPhase {
  Start
  Method
  Location
  Version
  Headers
  End
} derive(Show, Eq)

///|
priv struct HttpRequestParser {
  mut http_method : String?
  mut location : String?
  mut http_version : String?
  headers : Map[String, String]
  mut phase : HttpRequestParserPhase
  buffer : @buffer.T
  mut current_header_name : String?
  mut is_parsing_header_name : Bool
  mut expect_ln_after_cr : Bool
  mut expect_header_or_end : Bool
}

///|
fn HttpRequestParser::new() -> HttpRequestParser {
  HttpRequestParser::{
    http_method: None,
    location: None,
    http_version: None,
    headers: Map::new(),
    phase: HttpRequestParserPhase::Start,
    buffer: @buffer.new(size_hint=4096),
    current_header_name: None,
    is_parsing_header_name: true,
    expect_ln_after_cr: false,
    expect_header_or_end: false,
  }
}

///|
fn HttpRequestParser::parse(
  self : HttpRequestParser,
  byte : Byte
) -> Bool!@encoding.DecodingError {
  match self.phase {
    HttpRequestParserPhase::Start =>
      if byte != b' ' && byte != b'\r' && byte != b'\n' {
        self.buffer.write_byte(byte)
        self.phase = HttpRequestParserPhase::Method
      }
    HttpRequestParserPhase::Method =>
      if byte == b' ' {
        let data = self.buffer.to_bytes()
        let str = @encoding.decode!(data, encoding=UTF8)
        self.buffer.reset()
        self.http_method = Some(str)
        self.phase = HttpRequestParserPhase::Location
      } else {
        self.buffer.write_byte(byte)
      }
    HttpRequestParserPhase::Location =>
      if byte == b' ' {
        let data = self.buffer.to_bytes()
        let str = @encoding.decode!(data, encoding=UTF8)
        self.buffer.reset()
        self.location = Some(str)
        self.phase = HttpRequestParserPhase::Version
      } else {
        self.buffer.write_byte(byte)
      }
    HttpRequestParserPhase::Version =>
      if byte == b'\r' {
        let data = self.buffer.to_bytes()
        let str = @encoding.decode!(data, encoding=UTF8)
        self.buffer.reset()
        self.http_version = Some(str)
        self.phase = HttpRequestParserPhase::Headers
        self.expect_ln_after_cr = true
      } else {
        self.buffer.write_byte(byte)
      }
    HttpRequestParserPhase::Headers =>
      if self.expect_ln_after_cr {
        self.expect_ln_after_cr = false
        if byte == b'\n' {
          if self.expect_header_or_end {
            self.phase = HttpRequestParserPhase::End
            self.expect_header_or_end = false
            return true
          } else {
            let data = self.buffer.to_bytes()
            let value = @encoding.decode!(data, encoding=UTF8)
            self.buffer.reset()
            if not(self.current_header_name.is_empty()) {
              let name = self.current_header_name.unwrap()
              self.headers.set(name, value)
              self.current_header_name = None
            }
            self.is_parsing_header_name = true
            self.expect_header_or_end = true
          }
        } else {
          self.buffer.write_byte(b'\r')
          self.buffer.write_byte(byte)
        }
      } else if byte == b'\r' {
        self.expect_ln_after_cr = true
      } else if self.expect_header_or_end {
        self.expect_header_or_end = false
        self.buffer.write_byte(byte)
      } else if self.is_parsing_header_name && byte == b':' {
        let data = self.buffer.to_bytes()
        let name = @encoding.decode!(data, encoding=UTF8)
        self.current_header_name = Some(name)
        self.buffer.reset()
        self.is_parsing_header_name = false
      } else if not(self.is_parsing_header_name) &&
        byte == b' ' &&
        self.buffer.length() == 0 {
        // skip space after header name
      } else {
        self.buffer.write_byte(byte)
      }
    HttpRequestParserPhase::End => return true
  }
  return false
}

///|
fn HttpRequestParser::is_complete(self : HttpRequestParser) -> Bool {
  return self.phase == HttpRequestParserPhase::End
}

///|
test "HttpRequestParser" {
  let parser = HttpRequestParser::new()
  let bytes = b"GET / HTTP/1.1\r\nHost: example.com\r\nA: B\r\n\r\n"
  for byte in bytes {
    if parser.parse!(byte) {
      break
    }
  }
  assert_eq!(parser.is_complete(), true)
  assert_eq!(parser.http_method, Some("GET"))
  assert_eq!(parser.location, Some("/"))
  assert_eq!(parser.http_version, Some("HTTP/1.1"))
  assert_eq!(parser.headers.get("Host"), Some("example.com"))
  assert_eq!(parser.headers.get("A"), Some("B"))
}
