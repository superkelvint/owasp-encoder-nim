# test_uriencoder.nim
import unittest
import encoder_test_suite_builder # Our helper module
import uriencoder                # Your uriencoder.nim module
import std/unicode # for Rune

# Helper to create string from a Unicode codepoint
proc cp(codepoint: int): string =
  let r: Rune = Rune(codepoint)
  return $r

# This helper proc contains all the logic you had in your 'for' loop
proc runModeTest(mode: URIEncoderMode) =
  # Instantiate a new builder and encoder for the current mode
  var builder = newEncoderTestSuiteBuilder(
    $mode, # Use the mode name for the suite name
    newURIEncoder(mode), 
    "-safe-", 
    "<>")
  
  # Define the character sets
  builder = builder.encoded(0, MaxCodePoint)
  builder = builder.invalid(0xD800, 0xDFFF) # Surrogates (invalid in UTF-8/URI contexts)
  
  # Characters safe in all modes (unreserved)
  builder = builder.valid("-._~")
  builder = builder.valid('a'.int, 'z'.int)
  builder = builder.valid('A'.int, 'Z'.int)
  builder = builder.valid('0'.int, '9'.int)

  case mode:
  of COMPONENT:
    # reserved gen-delims - must be encoded in COMPONENT mode
    builder = builder.encode("%3A", ":")
    builder = builder.encode("%2F", "/")
    builder = builder.encode("%3F", "?")
    builder = builder.encode("%23", "#")
    builder = builder.encode("%5B", "[")
    builder = builder.encode("%5D", "]")
    builder = builder.encode("%40", "@")

    # reserved sub-delims - must be encoded in COMPONENT mode
    builder = builder.encode("%21", "!")
    builder = builder.encode("%24", "$")
    builder = builder.encode("%26", "&")
    builder = builder.encode("%27", "'")
    builder = builder.encode("%28", "(")
    builder = builder.encode("%29", ")")
    builder = builder.encode("%2A", "*")
    builder = builder.encode("%2B", "+")
    builder = builder.encode("%2C", ",")
    builder = builder.encode("%3B", ";")
    builder = builder.encode("%3D", "=")
  of FULL_URI:
    # Test a full URL which is mostly left unencoded in FULL_URI mode
    builder = builder.encodeWithName(
        "full-url",
        "http://www.owasp.org/index.php?foo=bar&baz#fragment",
        "http://www.owasp.org/index.php?foo=bar&baz#fragment")
    # reserved characters that are valid/safe in FULL_URI mode
    builder = builder.valid(":/?#[]@!$&'()*+,;=")
  
  # simple test of some unencoded characters
  builder = builder.encode("abcABC123", "abcABC123")

  # ASCII characters encoded in all modes
  builder = builder.encode("%20", " ") # Space
  builder = builder.encode("%22", "\"")
  builder = builder.encode("%25", "%") # Percent sign itself
  builder = builder.encode("%3C", "<")
  builder = builder.encode("%3E", ">")
  builder = builder.encode("%5C", "\\")
  builder = builder.encode("%5E", "^")
  builder = builder.encode("%60", "`")
  builder = builder.encode("%7B", "{")
  builder = builder.encode("%7C", "|")
  builder = builder.encode("%7D", "}")

  # UTF-8 multi-byte handling
  builder = builder.encodeWithName("2-byte-utf-8", "%C2%A0", "\u00a0") # No-Break Space
  builder = builder.encodeWithName("3-byte-utf-8", "%E0%A0%80", "\u0800") # Start of 3-byte range
      
  builder = builder.encodeWithName("4-byte-utf-8", "%F0%90%80%80",
    cp(0x10000)) # Plane 1 character

  # Isolated surrogate codepoints (should result in invalid/error character)
  builder = builder.encodeWithName("missing-low-surrogate", "-", "\uD800") # High surrogate alone
  builder = builder.encodeWithName("missing-high-surrogate", "-", "\uDC00") # Low surrogate alone

  # Run the generated suites
  builder = builder.validSuite()
  builder = builder.invalidSuite('-')
  builder = builder.encodedSuite()

  # No 'build()' or 'run()' call is needed. The tests have already run.

# This is the main test suite
suite "URIEncoder Tests":
  
  test "Mode: COMPONENT":
    # This test block runs all tests for the COMPONENT mode
    runModeTest(COMPONENT)

  test "Mode: FULL_URI":
    # This test block runs all tests for the FULL_URI mode
    runModeTest(FULL_URI)