import unittest
import std/strutils, std/strformat
import std/unicode
import encoder

type
  EncoderTestSuiteBuilder* = ref object
    suiteName: string
    encoder: Encoder
    safeAffix: string
    unsafeAffix: string
    validSet: set[uint16]      # Track codepoints up to 0xFFFF
    validSetHigh: seq[bool]    # Track codepoints above 0xFFFF up to MaxCodePoint
    invalidSet: set[uint16]
    invalidSetHigh: seq[bool]
    encodedSet: set[uint16]
    encodedSetHigh: seq[bool]

const
  MaxCodePoint* = 0x10FFFF
  BoundaryHigh = 0x10000

# Helper: Java's debugEncode
proc debugEncode(input: string): string =
  result = newStringOfCap(input.len * 2)
  for ch in input.runes:
    case ch.int:
    of '\\'.int: result.add("\\\\")
    of '\''.int: result.add("\\\'")
    of '\"'.int: result.add("\\\"")
    of '\r'.int: result.add("\\r")
    of '\n'.int: result.add("\\n")
    of '\t'.int: result.add("\\t")
    else:
      if ch.int >= 32 and ch.int <= 126:
        result.add($ch)
      else:
        if ch.int <= 0xFFFF:
          result.add(fmt"\\u{ch.int:04x}")
        else:
          result.add(fmt"\\U{ch.int:08x}")

# Helper procs to add/remove/check codepoints from sets
proc inclCodepoint(builder: EncoderTestSuiteBuilder, s: var set[uint16], high: var seq[bool], cp: int) =
  if cp < BoundaryHigh:
    s.incl(cp.uint16)
  else:
    let idx = cp - BoundaryHigh
    if idx >= high.len:
      high.setLen(idx + 1)
    high[idx] = true

proc exclCodepoint(builder: EncoderTestSuiteBuilder, s: var set[uint16], high: var seq[bool], cp: int) =
  if cp < BoundaryHigh:
    s.excl(cp.uint16)
  else:
    let idx = cp - BoundaryHigh
    if idx < high.len:
      high[idx] = false

proc containsCodepoint(s: set[uint16], high: seq[bool], cp: int): bool =
  if cp < BoundaryHigh:
    return cp.uint16 in s
  else:
    let idx = cp - BoundaryHigh
    return idx < high.len and high[idx]

# Constructor
proc newEncoderTestSuiteBuilder*(suiteName: string, encoder: Encoder, safeAffix, unsafeAffix: string): EncoderTestSuiteBuilder =
  new(result)
  result.suiteName = suiteName
  result.encoder = encoder
  result.safeAffix = safeAffix
  result.unsafeAffix = unsafeAffix
  result.validSet = {}
  result.validSetHigh = @[]
  result.invalidSet = {}
  result.invalidSetHigh = @[]
  result.encodedSet = {}
  result.encodedSetHigh = @[]

# Core assertion helper - verifies correctness of encoding
proc checkEncode(builder: EncoderTestSuiteBuilder, expected: string, input: string) =
  let actual = builder.encoder.encode(input)
  
  if expected != actual:
    var msg = fmt"encode({debugEncode(input)}) -- expected: {expected}, got: {actual}"
    assert(false, msg)

# Helper to verify the no-allocation optimization
# Use this when you have a reference to the original string
proc checkEncodeOptimization(builder: EncoderTestSuiteBuilder, input: string) =
  let actual = builder.encoder.encode(input)
  
  # If no encoding was needed, verify same object
  if input == actual and input.len > 0:
    if addr(input[0]) != addr(actual[0]):
      let msg = fmt"Input {debugEncode(input)} was not modified, but a new string was allocated (optimization failed)."
      assert(false, msg)

# `encode(name, expected, input)`
proc encodeWithName*(builder: EncoderTestSuiteBuilder, name: string, expected: string, input: string): EncoderTestSuiteBuilder =
  builder.checkEncode(expected, input)
  builder.checkEncodeOptimization(input)
  
  builder.checkEncode(builder.safeAffix & expected, builder.safeAffix & input)
  builder.checkEncode(expected & builder.safeAffix, input & builder.safeAffix)
  builder.checkEncode(builder.safeAffix & expected & builder.safeAffix,
                builder.safeAffix & input & builder.safeAffix)

  let escapedAffix = builder.encoder.encode(builder.unsafeAffix)
  builder.checkEncode(escapedAffix & expected, builder.unsafeAffix & input)
  builder.checkEncode(expected & escapedAffix, input & builder.unsafeAffix)
  builder.checkEncode(escapedAffix & expected & escapedAffix,
                builder.unsafeAffix & input & builder.unsafeAffix)
  
  return builder


# `encode(expected, input)`
proc encode*(builder: EncoderTestSuiteBuilder, expected: string, input: string): EncoderTestSuiteBuilder =
  let debugInput = debugEncode(input)
  return builder.encodeWithName(fmt"input: {debugInput}", expected, input)

# Convert codepoint to string
proc cp(codepoint: int): string =
  let r: Rune = Rune(codepoint)
  return $r

# Invalid character set operations
proc invalid*(builder: EncoderTestSuiteBuilder, chars: string): EncoderTestSuiteBuilder =
  for ch in chars.runes:
    builder.inclCodepoint(builder.invalidSet, builder.invalidSetHigh, ch.int)
    builder.exclCodepoint(builder.validSet, builder.validSetHigh, ch.int)
    builder.exclCodepoint(builder.encodedSet, builder.encodedSetHigh, ch.int)
  return builder

proc invalid*(builder: EncoderTestSuiteBuilder, min, max: int): EncoderTestSuiteBuilder =
  for i in min .. max:
    builder.inclCodepoint(builder.invalidSet, builder.invalidSetHigh, i)
    builder.exclCodepoint(builder.validSet, builder.validSetHigh, i)
    builder.exclCodepoint(builder.encodedSet, builder.encodedSetHigh, i)
  return builder

# Valid character set operations
proc valid*(builder: EncoderTestSuiteBuilder, chars: string): EncoderTestSuiteBuilder =
  for ch in chars.runes:
    builder.inclCodepoint(builder.validSet, builder.validSetHigh, ch.int)
    builder.exclCodepoint(builder.invalidSet, builder.invalidSetHigh, ch.int)
    builder.exclCodepoint(builder.encodedSet, builder.encodedSetHigh, ch.int)
  return builder

proc valid*(builder: EncoderTestSuiteBuilder, min, max: int): EncoderTestSuiteBuilder =
  for i in min .. max:
    builder.inclCodepoint(builder.validSet, builder.validSetHigh, i)
    builder.exclCodepoint(builder.invalidSet, builder.invalidSetHigh, i)
    builder.exclCodepoint(builder.encodedSet, builder.encodedSetHigh, i)
  return builder

# Encoded character set operations
proc encoded*(builder: EncoderTestSuiteBuilder, chars: string): EncoderTestSuiteBuilder =
  for ch in chars.runes:
    builder.inclCodepoint(builder.encodedSet, builder.encodedSetHigh, ch.int)
    builder.exclCodepoint(builder.validSet, builder.validSetHigh, ch.int)
    builder.exclCodepoint(builder.invalidSet, builder.invalidSetHigh, ch.int)
  return builder

proc encoded*(builder: EncoderTestSuiteBuilder, min, max: int): EncoderTestSuiteBuilder =
  for i in min .. max:
    builder.inclCodepoint(builder.encodedSet, builder.encodedSetHigh, i)
    builder.exclCodepoint(builder.validSet, builder.validSetHigh, i)
    builder.exclCodepoint(builder.invalidSet, builder.invalidSetHigh, i)
  return builder

# Calculate cardinality of all sets combined
proc totalCardinality(builder: EncoderTestSuiteBuilder): int =
  result = builder.validSet.card + builder.invalidSet.card + builder.encodedSet.card
  for b in builder.validSetHigh:
    if b: inc(result)
  for b in builder.invalidSetHigh:
    if b: inc(result)
  for b in builder.encodedSetHigh:
    if b: inc(result)

# Valid suite test
proc validSuite*(builder: EncoderTestSuiteBuilder): EncoderTestSuiteBuilder =
  let cardinality = builder.totalCardinality()
  if cardinality != MaxCodePoint + 1:
    raise newException(AssertionError, 
      fmt"incomplete coverage: {cardinality} != {MaxCodePoint + 1}")
  
  # Test low codepoints (0-0xFFFF)
  for cp in builder.validSet:
    builder.checkEncode($cp.Rune, $cp.Rune)
  
  # Test high codepoints (0x10000+)
  for i in 0 ..< builder.validSetHigh.len:
    if builder.validSetHigh[i]:
      let codepoint = i + BoundaryHigh
      builder.checkEncode(cp(codepoint), cp(codepoint))
  
  return builder

# Invalid suite test
proc invalidSuite*(builder: EncoderTestSuiteBuilder, invalidChar: char): EncoderTestSuiteBuilder =
  let invalidString = $invalidChar
  
  # Test low codepoints
  for cp in builder.invalidSet:
    let input = $cp.Rune
    let actual = builder.encoder.encode(input)
    if invalidString != actual:
      assert(false, fmt"""encode("{debugEncode(input)}") -- expected: "{invalidString}", got: "{debugEncode(actual)}"""")
  
  # Test high codepoints
  for i in 0 ..< builder.invalidSetHigh.len:
    if builder.invalidSetHigh[i]:
      let codepoint = i + BoundaryHigh
      let input = cp(codepoint)
      let actual = builder.encoder.encode(input)
      if invalidString != actual:
        assert(false, fmt"""encode("{debugEncode(input)}") -- expected: "{invalidString}", got: "{debugEncode(actual)}"""")
  
  return builder

# Encoded suite test
proc encodedSuite*(builder: EncoderTestSuiteBuilder): EncoderTestSuiteBuilder =
  # Test low codepoints
  for cp in builder.encodedSet:
    let input = $cp.Rune
    let actual = builder.encoder.encode(input)
    if actual == input:
      assert(false, fmt"input={debugEncode(input)} was not encoded")
  
  # Test high codepoints
  for i in 0 ..< builder.encodedSetHigh.len:
    if builder.encodedSetHigh[i]:
      let codepoint = i + BoundaryHigh
      let input = cp(codepoint)
      let actual = builder.encoder.encode(input)
      if actual == input:
        assert(false, fmt"input={debugEncode(input)} was not encoded")
  
  return builder