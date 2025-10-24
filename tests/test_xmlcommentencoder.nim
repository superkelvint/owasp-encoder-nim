# test_xmlcommentencoder.nim
import unittest
import encoder_test_suite_builder 
import xmlcommentencoder         
import encoder                   
import std/unicode # for Rune

# Helper to create string from a Unicode codepoint
proc cp(codepoint: int): string =
  let r: Rune = Rune(codepoint)
  return $r

suite "XMLCommentEncoder Tests":

  test "Builder Suite":
    # This block ports the EncoderTestSuiteBuilder chain
    var builder = newEncoderTestSuiteBuilder(
      "XMLCommentEncoder",
      newXMLCommentEncoder(),
      "(safe)", # safeAffix
      "--"      # unsafeAffix
    )

    var same = "a 4344 b"
    builder = builder.encode(same, same)
    same = "<\"&'>"
    builder = builder.encode(same, same) # valid in comments

    builder = builder.invalid(0, 0x1f)
    builder = builder.valid("\t\r\n")
    builder = builder.valid(' '.int, MaxCodePoint)
    builder = builder.invalid(0x7f, 0x9f)
    builder = builder.valid("\u0085") # NEL
    builder = builder.encoded("-") # '-' is not "valid" as it has special rules
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

    builder = builder.validSuite()
    builder = builder.invalidSuite(INVALID_CHARACTER_REPLACEMENT)
    # Note: encodedSuite() is not called, matching the Java test

  test "Encode Hyphens":
    let encoder = newXMLCommentEncoder()
    check encoder.encode("--") == "-~"
    check encoder.encode("ab--cd") == "ab-~cd"

  test "Encode Hyphen At End":
    let encoder = newXMLCommentEncoder()
    check encoder.encode("-") == "~"
    check encoder.encode("abc-") == "abc~"

  test "Encode Hyphen Bar":
    let encoder = newXMLCommentEncoder()
    check encoder.encode("-----------") == "-~-~-~-~-~~"