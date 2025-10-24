# test_htmlencoder.nim
import unittest
import encoder_test_suite_builder # Our helper module
import htmlencoder                # Your htmlencoder.nim module
import std/unicode # for Rune

# Helper to create string from a Unicode codepoint
proc cp(codepoint: int): string =
  let r: Rune = Rune(codepoint)
  return $r

suite "HTMLEncoder Tests":

  test "Builder Suite":
    var builder = newEncoderTestSuiteBuilder(
      "HTMLEncoder",
      newHTMLEncoder(),
      "-safe-", # safeAffix
      "-&-"     # unsafeAffix
    )

    builder = builder.encode("&amp;", "&")
    builder = builder.encode("&gt;", ">")
    builder = builder.encode("&lt;", "<")
    builder = builder.encode("&#39;", "'")
    builder = builder.encode("&#34;", "\"")
    builder = builder.encodeWithName("space", "&#32;", " ")
    builder = builder.encodeWithName("tab", "&#9;", "\t")
    builder = builder.encodeWithName("LF", "&#10;", "\n")
    builder = builder.encodeWithName("FF", "&#12;", "\f")
    builder = builder.encodeWithName("CR", "&#13;", "\r")
    builder = builder.encode("&#96;", "`")
    builder = builder.encode("&#47;", "/")
    builder = builder.encode("&#133;", "\u0085") # NEL
    builder = builder.encode("safe", "safe")
    builder = builder.encodeWithName("unencoded-and-encoded", "unencoded&amp;encoded", "unencoded&encoded")
    builder = builder.encodeWithName("invalid-control-characters", "-b-", cp(0) & "b" & cp(0x16))
    # builder = builder.encodeWithName("valid-surrogate-pair", "\uD800\uDC00", "\uD800\uDC00")
    # The Java test "\ud800\udc00" represents codepoint 0x10000.
    # The correct Nim/UTF-8 literal for this is "\u{00010000}".
    builder = builder.encodeWithName("valid-surrogate-pair", "\u{00010000}", "\u{00010000}")
    builder = builder.encodeWithName("missing-low-surrogate", "-", "\uD800")
    builder = builder.encodeWithName("missing-high-surrogate", "-", "\uDC00")
    builder = builder.encodeWithName("valid-upper-char", "\uFFFD", "\uFFFD")
    builder = builder.encodeWithName("invalid-upper-char", "-", "\uFFFF")
    builder = builder.encodeWithName("line-separator", "&#8232;", "\u2028")
    builder = builder.encodeWithName("paragraph-separator", "&#8233;", "\u2029")

    builder = builder.invalid(0, 0x1f)
    builder = builder.valid("\t\r\n\f") # \f (0x0C) is encoded, but validSuite doesn't check for that
    builder = builder.valid(' '.int, MaxCodePoint)
    builder = builder.invalid(0x7f, 0x9f)
    builder = builder.valid("\u0085") # NEL (0x85)
    builder = builder.encoded("&><'\"/`= \r\n\t\f\u0085\u2028\u2029")
    builder = builder.invalid(0xD800, 0xDFFF) # Surrogates
    builder = builder.invalid(0xfdd0, 0xfdef)
    builder = builder.invalid(0xfffe, 0xffff)
    builder = builder.invalid(0x1fffe, 0x1ffff)
    builder = builder.invalid(0x2fffe, 0x2ffff)
    builder = builder.invalid(0x3fffe, 0x3ffff)
    builder = builder.invalid(0x4fffe, 0x4ffff)
    builder = builder.invalid(0x5fffe, 0x5ffff)
    builder = builder.invalid(0x6fffe, 0x6ffff)
    builder = builder.invalid(0x7fffe, 0x7ffff)
    builder = builder.invalid(0x8fffe, 0x8ffff)
    builder = builder.invalid(0x9fffe, 0x9ffff)
    builder = builder.invalid(0xafffe, 0xaffff)
    builder = builder.invalid(0xbfffe, 0xbffff)
    builder = builder.invalid(0xcfffe, 0xcffff)
    builder = builder.invalid(0xdfffe, 0xdffff)
    builder = builder.invalid(0xefffe, 0xeffff)
    builder = builder.invalid(0xffffe, 0xfffff)
    builder = builder.invalid(0x10fffe, 0x10ffff)

    # Run the generated suites
    builder = builder.validSuite()
    builder = builder.invalidSuite(INVALID_CHARACTER_REPLACEMENT)
    builder = builder.encodedSuite()