# test_javascriptencoder.nim
import unittest
import encoder_test_suite_builder
import javascriptencoder
import std/unicode

# Helper to create string from a Unicode codepoint
proc cp(codepoint: int): string =
  let r: Rune = Rune(codepoint)
  return $r

suite "JavaScriptEncoder Tests":

  for asciiOnly in [false, true]:
    for mode in low(JavaScriptEncoderMode)..high(JavaScriptEncoderMode):
      let suiteName = $mode & (if asciiOnly: " (ASCII_ONLY)" else: " (UNICODE)")

      test suiteName:
        var builder = newEncoderTestSuiteBuilder(
          "JavascriptEncoder",
          newJavaScriptEncoder(mode, asciiOnly),
          "(safe)",
          "(\\)"
        )

        builder = builder.encoded(0, 0x1f)
        builder = builder.valid(' '.int, '~'.int)
        builder = builder.encoded("\\'\"")

        case mode
        of SOURCE, BLOCK:
          builder = builder.encode("\\\"", "\"")
          builder = builder.encode("\\'", "'")
        of HTML, ATTRIBUTE:
          builder = builder.encode("\\\\x22", "\"")
          builder = builder.encode("\\\\x27", "'")

        case mode
        of BLOCK, HTML:
          builder = builder.encode("\\/", "/")
          builder = builder.encode("\\-", "-")
          builder = builder.encoded("/-")
        else:
          builder = builder.encode("/", "/")

        if mode != SOURCE:
          builder = builder.encoded("&")

        builder = builder.encode("\\\\", "\\")
        builder = builder.encodeWithName("backspace", "\\b", "\b")
        builder = builder.encodeWithName("tab", "\\t", "\t")
        builder = builder.encodeWithName("LF", "\\n", "\n")
        builder = builder.encodeWithName("vtab", "\\\\x0b", cp(0x0b))
        builder = builder.encodeWithName("FF", "\\f", "\f")
        builder = builder.encodeWithName("CR", "\\r", "\r")
        builder = builder.encodeWithName("NUL", "\\\\x00", cp(0))
        builder = builder.encodeWithName("Line Separator", "\\\\u2028", "\u2028")
        builder = builder.encodeWithName("Paragraph Separator", "\\\\u2029", "\u2029")
        builder = builder.encode("abc", "abc")
        builder = builder.encode("ABC", "ABC")

        if not asciiOnly:
          builder = builder.encodeWithName("unicode", "\u1234", "\u1234")
          builder = builder.encodeWithName("high-ascii", "\u00ff", "\u00ff")

          # Add valid ranges, but exclude the separators
          builder = builder.valid(0x7f, 0x2028 - 1)
          builder = builder.valid(0x2028 + 1, 0x2029 - 1)
          builder = builder.valid(0x2029 + 1, MaxCodePoint)

          builder = builder.encoded("\u2028\u2029")
        else:
          builder = builder.encodeWithName("unicode", "\\\\u1234", "\u1234")
          builder = builder.encodeWithName("high-ascii", "\\\\xff", "\u00ff")
          builder = builder.encoded(0x7f, MaxCodePoint)
        
        # Run suites
        builder = builder.validSuite()
        builder = builder.encodedSuite()