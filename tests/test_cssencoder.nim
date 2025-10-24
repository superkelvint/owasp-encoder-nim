# test_cssencoder.nim
import unittest
import encoder_test_suite_builder # Our helper module
import cssencoder                # Your cssencoder.nim module
import std/unicode # for Rune

# Helper to create string from a Unicode codepoint
proc cp(codepoint: int): string =
  let r: Rune = Rune(codepoint)
  return $r

# This helper proc contains all the logic from the Java suite() method
proc runModeTest(mode: CSSEncoderMode) =
  # Instantiate a new builder and encoder for the current mode
  var builder = newEncoderTestSuiteBuilder(
    $mode, # Use the mode name for the suite name
    newCSSEncoder(mode),
    "safe", # safeAffix
    "'"     # unsafeAffix
  )

  # --- Port of common builder chain from CSSEncoderTest.java ---
  builder = builder.encode("\\27", "'")
  builder = builder.encode("safe", "safe")
  builder = builder.encodeWithName("required-space-after-encode", "\\27 1", "'1")
  builder = builder.encodeWithName("no-space-required-after-encode", "\\27x", "'x")
  builder = builder.encodeWithName("NUL", "\\0", cp(0))
  builder = builder.encodeWithName("DEL", "\\7f", cp(0x7f))

  builder = builder.encoded(0, 0x9F) # 0 to '\237' (octal 237 = 159 = 0x9F)
  builder = builder.valid("!#$%")
  builder = builder.valid('*'.int, '~'.int)
  builder = builder.encoded("\\")
  builder = builder.valid(0xA0, MaxCodePoint) # '\240' (octal 240 = 160 = 0xA0)
  builder = builder.encoded(0x2028, 0x2029)
  builder = builder.encodeWithName("Line Separator", "\\2028", cp(0x2028))
  builder = builder.encodeWithName("Paragraph Separator", "\\2029", cp(0x2029))
  builder = builder.invalid(0xD800, 0xDFFF) # Surrogates

  # --- Port of mode-specific switch block ---
  case mode:
  of STRING:
    builder = builder.valid(' '.int, '~'.int)
  of URL:
    builder = builder.encodeWithName("url-space-test", "-\\20-", "- -")

  # --- Port of common suffix chain ---
  builder = builder.encoded("\"\'\\<&/>")

  # Run the generated suites
  builder = builder.validSuite()
  builder = builder.invalidSuite(INVALID_REPLACEMENT_CHARACTER)
  builder = builder.encodedSuite()

# This is the main test suite
suite "CSSEncoder Tests":

  test "Mode: STRING":
    # This test block runs all tests for the STRING mode
    runModeTest(STRING)

  test "Mode: URL":
    # This test block runs all tests for the URL mode
    runModeTest(URL)