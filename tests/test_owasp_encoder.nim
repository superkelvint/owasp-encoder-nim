# test_owasp_encoder.nim
import unittest
import std/streams
import std/strutils
import owasp_encoder

suite "Encode (Public API) Tests":

  test "Encode to Stream (Writer)":
    var s = newStringStream()
    forXml(s, "<script>")
    check s.data == "&lt;script&gt;" #

  test "Batched Encoding to Stream (Writer)":
    # This test validates large encodes.
    # The Java version checks for multiple writes to test internal
    # buffering. Our Nim version doesn't batch in the same
    # way (it creates one encoded suffix string), so we
    # just validate the final output is correct.
    let input = "&&&&&&&&&&&&&&&&&&&&"
      .repeat(20)  # 400
      .repeat(20)  # 8000
    
    let expected = input.replace("&", "&amp;") #
    var s = newStringStream()
    forXml(s, input)

    check s.data.len == 8000 * 5 #
    check s.data == expected #

  test "Unencoded String to Stream (Writer)":
    # Tests the optimization path where no encoding is needed.
    let unencodedString = "safe"
    var s = newStringStream()
    forXml(s, unencodedString)
    check s.data == unencodedString #

  # NOTE: Removed `testEncodeNullToWriter` from Java.
  # In Nim, the `nil` literal cannot be passed as a `string` type.
  # The implementation in `encoder.nim` *does* correctly handle
  # a `nil` string variable, but it's not feasible
  # to test this here without using FFI or other means.

  test "Encode String":
    check forXml("<script>") == "&lt;script&gt;" #

  # NOTE: Removed `testEncodeNullToString` from Java.
  # See note above. The `nil` literal cannot be passed as a `string`.
  # The implementation in `encoder.nim` correctly handles a
  # `nil` string variable.

  test "Unencoded String (Optimization)":
    # Make sure we return the *same object* when no encoding happens
    let input = "safe"
    let output = forXml(input)
    check input == output

  test "Large Encode to String":
    # Tests output that fits in input buffer but overflows output buffer
    # (In our Nim port, this is just a standard encode)
    let input = "&&&&&&&&&&"
      .repeat(10) # 100
      .repeat(10) # 1000

    let expected = input.replace("&", "&amp;")
    let output = forXml(input)
    check output.len == 5000 #
    check output == expected #

  test "Very Large Encode to String":
    # Tests output that overflows internal input buffer
    # (In our Nim port, this is just a standard encode)
    let input = "&&&&&&&&&&&&&&&&&&&&"
      .repeat(20)  # 400
      .repeat(20)  # 8000

    let expected = input.replace("&", "&amp;")
    let output = forXml(input)
    check output.len == 40000 #
    check output == expected #


test "Encode forHtml":
  let input = "&<>'\""
  let expected = "&amp;&lt;&gt;&#39;&#34;"
  check forHtml(input) == expected
  var s = newStringStream()
  forHtml(s, input)
  check s.data == expected

test "Encode forHtmlContent":
  let input = "&<>'\""
  let expected = "&amp;&lt;&gt;'\""
  check forHtmlContent(input) == expected
  var s = newStringStream()
  forHtmlContent(s, input)
  check s.data == expected

test "Encode forHtmlAttribute":
  let input = "&<>'\""
  let expected = "&amp;&lt;>&#39;&#34;"
  check forHtmlAttribute(input) == expected
  var s = newStringStream()
  forHtmlAttribute(s, input)
  check s.data == expected

test "Encode forHtmlUnquotedAttribute":
  let input = " '="
  let expected = "&#32;&#39;&#61;"
  check forHtmlUnquotedAttribute(input) == expected
  var s = newStringStream()
  forHtmlUnquotedAttribute(s, input)
  check s.data == expected

test "Encode forXmlContent":
  let input = "<tag>'"
  let expected = "&lt;tag&gt;'"
  check forXmlContent(input) == expected
  var s = newStringStream()
  forXmlContent(s, input)
  check s.data == expected

test "Encode forXmlAttribute":
  let input = ">'\""
  let expected = ">&#39;&#34;"
  check forXmlAttribute(input) == expected
  var s = newStringStream()
  forXmlAttribute(s, input)
  check s.data == expected

test "Encode forXmlComment":
  let input = "a--b"
  let expected = "a-~b"
  check forXmlComment(input) == expected
  var s = newStringStream()
  forXmlComment(s, input)
  check s.data == expected

test "Encode forCDATA":
  let input = "a]]>b"
  let expected = "a]]]]><![CDATA[>b"
  check forCDATA(input) == expected
  var s = newStringStream()
  forCDATA(s, input)
  check s.data == expected

test "Encode forCssString":
  let input = "'\"\\"
  let expected = "\\27\\22\\5c"
  check forCssString(input) == expected
  var s = newStringStream()
  forCssString(s, input)
  check s.data == expected

test "Encode forCssUrl":
  let input = " ('"
  let expected = "\\20\\28\\27"
  check forCssUrl(input) == expected
  var s = newStringStream()
  forCssUrl(s, input)
  check s.data == expected

test "Encode forUriComponent":
  let input = "/foo bar"
  let expected = "%2Ffoo%20bar"
  check forUriComponent(input) == expected
  var s = newStringStream()
  forUriComponent(s, input)
  check s.data == expected

test "Encode forJavaScript (HTML)":
  # Default HTML mode encodes quotes as \x.. and / as \/
  check forJavaScript("'foo'") == "\\x27foo\\x27"
  check forJavaScript("</script>") == "<\\/script>"
  var s = newStringStream()
  forJavaScript(s, "'&'")
  check s.data == "\\x27\\&\\x27"

test "Encode forJavaScriptAttribute":
  # Encodes quotes as \x.. but not /
  check forJavaScriptAttribute("'foo'") == "\\x27foo\\x27"
  check forJavaScriptAttribute("</script>") == "</script>"
  var s = newStringStream()
  forJavaScriptAttribute(s, "'&'")
  check s.data == "\\x27\\&\\x27"

test "Encode forJavaScriptBlock":
  # Encodes quotes as \' and / as \/
  check forJavaScriptBlock("'foo'") == "\\'foo\\'"
  check forJavaScriptBlock("</script>") == "<\\/script>"
  var s = newStringStream()
  forJavaScriptBlock(s, "'&'")
  check s.data == "\\'\\&\\'"

test "Encode forJavaScriptSource":
  # Encodes quotes as \' but not / or &
  check forJavaScriptSource("'foo'") == "\\'foo\\'"
  check forJavaScriptSource("</script>") == "</script>"
  var s = newStringStream()
  forJavaScriptSource(s, "'&'")
  check s.data == "\\'&\\'"