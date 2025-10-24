# xmlencoder.nim
import encoder
import std/unicode

const
  INVALID_CHARACTER_REPLACEMENT* = ' '

  # [2] Char ::= #x9 | #xA | #xD | [#x20-#xD7FF] | ...
  BASE_VALID_MASK = (1'u64 shl 9) or (1'u64 shl 10) or (1'u64 shl 13) # \t, \n, \r

  # Mask for all chars from 32 (' ') to 63 ('?')
  VALID_ASCII_MASK = (0xFFFFFFFFFFFFFFFF'u64 shl 32)

  # Unicode constants
  DEL = 0x7F
  NEL = 0x85
  MAX_C1_CTRL_CHAR = 0x9F
  MIN_HIGH_SURROGATE = 0xD800
  MAX_HIGH_SURROGATE = 0xDBFF
  MAX_LOW_SURROGATE = 0xDFFF

type
  XMLEncoderMode* = enum
    ALL
    CONTENT
    ATTRIBUTE
    SINGLE_QUOTED_ATTRIBUTE
    DOUBLE_QUOTED_ATTRIBUTE

  XMLEncoder* = ref object of Encoder
    validMask: uint64
    mode: XMLEncoderMode

proc newXMLEncoder*(mode: XMLEncoderMode): XMLEncoder =
  ## Constructor for the XMLEncoder
  new(result)
  result.mode = mode

  var encodeMask: uint64 = 0
  case mode
  of ALL:
    encodeMask = (1'u64 shl '&'.int) or (1'u64 shl '<'.int) or
                 (1'u64 shl '>'.int) or (1'u64 shl '\''.int) or
                 (1'u64 shl '"'.int)
  of CONTENT:
    encodeMask = (1'u64 shl '&'.int) or (1'u64 shl '<'.int) or
                 (1'u64 shl '>'.int)
  of ATTRIBUTE:
    encodeMask = (1'u64 shl '&'.int) or (1'u64 shl '<'.int) or
                 (1'u64 shl '\''.int) or (1'u64 shl '"'.int)
  of SINGLE_QUOTED_ATTRIBUTE:
    encodeMask = (1'u64 shl '&'.int) or (1'u64 shl '<'.int) or
                 (1'u64 shl '\''.int)
  of DOUBLE_QUOTED_ATTRIBUTE:
    encodeMask = (1'u64 shl '&'.int) or (1'u64 shl '<'.int) or
                 (1'u64 shl '"'.int)

  # Java logic: BASE_VALID_MASK | ((-1L << ' ') & ~(encodeMask))
  result.validMask = BASE_VALID_MASK or (VALID_ASCII_MASK and (not encodeMask))

proc decodeUtf8(s: string, i: int): (int, int) =
  ## Decodes a single UTF-8 codepoint from string `s` starting at index `i`.
  ## Returns (codepoint, next_index).
  ## Based on the logic originally in encodeInternal.
  if i >= s.len:
    return (0, i) # Should not happen if called correctly

  let b = s[i].uint8

  if (b and 0x80) == 0:
    # 1-byte sequence (0xxxxxxx)
    return (int(b), i + 1)
  elif (b and 0xE0) == 0xC0 and i + 1 < s.len:
    # 2-byte sequence (110xxxxx 10xxxxxx)
    let b2 = s[i + 1].uint8
    if (b2 and 0xC0) == 0x80:
      return (((b and 0x1F).int shl 6) or (b2 and 0x3F).int, i + 2)
    else:
      return (int(INVALID_CHARACTER_REPLACEMENT), i + 1) # Invalid 2-byte seq
  elif (b and 0xF0) == 0xE0 and i + 2 < s.len:
    # 3-byte sequence (1110xxxx 10xxxxxx 10xxxxxx)
    let b2 = s[i + 1].uint8
    let b3 = s[i + 2].uint8
    if (b2 and 0xC0) == 0x80 and (b3 and 0xC0) == 0x80:
      return (((b and 0x0F).int shl 12) or ((b2 and 0x3F).int shl 6) or (b3 and 0x3F).int, i + 3)
    else:
      return (int(INVALID_CHARACTER_REPLACEMENT), i + 1) # Invalid 3-byte seq
  elif (b and 0xF8) == 0xF0 and i + 3 < s.len:
    # 4-byte sequence (11110xxx 10xxxxxx 10xxxxxx 10xxxxxx)
    let b2 = s[i + 1].uint8
    let b3 = s[i + 2].uint8
    let b4 = s[i + 3].uint8
    if (b2 and 0xC0) == 0x80 and (b3 and 0xC0) == 0x80 and (b4 and 0xC0) == 0x80:
      return (((b and 0x07).int shl 18) or ((b2 and 0x3F).int shl 12) or
        ((b3 and 0x3F).int shl 6) or (b4 and 0x3F).int, i + 4)
    else:
      return (int(INVALID_CHARACTER_REPLACEMENT), i + 1) # Invalid 4-byte seq
  else:
    # Invalid start byte (e.g., 10xxxxxx) or truncated sequence
    return (int(INVALID_CHARACTER_REPLACEMENT), i + 1)

proc isNonCharacter(cp: int): bool =
  ## Checks if a codepoint is an XML non-character.
  if (cp >= 0xFDD0 and cp <= 0xFDEF): return true
  # Checks for 0xFFFE, 0xFFFF, 0x1FFFE, 0x1FFFF, etc.
  if (cp and 0xFFFF) in [0xFFFE, 0xFFFF]: return true
  return false

method firstEncodedOffset*(
    encoder: XMLEncoder, input: string, off: int, len: int
): int =
  ## Finds the first character position that needs encoding.
  ## This is a full-featured fast path that validates all Unicode.

  let n = off + len
  var i = off
  while i < n:
    let (cp, nextI) = decodeUtf8(input, i)

    # --- XMLEncoder-specific logic (from XMLEncoder.java) ---
    # This logic mirrors encodeInternal, but returns 'i' on failure
    # instead of adding to an output string.

    if cp == int(INVALID_CHARACTER_REPLACEMENT):
      return i # Invalid UTF-8 sequence

    elif cp < DEL: # 0-126
      if (cp > '>'.int) or ((encoder.validMask and (1'u64 shl cp)) != 0):
        discard # Valid ASCII, continue
      else:
        # Needs encoding or is invalid ASCII control
        case cp:
        of '&'.int, '<'.int, '>'.int, '\''.int, '"'.int:
          return i # Needs encoding
        else:
          return i # Invalid control char e.g. \0, \1, etc.

    elif cp < MIN_HIGH_SURROGATE: # 127 - 0xD7FF
      # Java logic: if (ch > Unicode.MAX_C1_CTRL_CHAR || ch == Unicode.NEL)
      if (cp > MAX_C1_CTRL_CHAR or cp == NEL):
        discard # Valid (e.g., 0xA0)
      else:
        # Invalid C0 control (0x7F) or C1 control (0x80-0x9F, excl 0x85)
        return i
    
    elif cp <= MAX_LOW_SURROGATE: # 0xD800 - 0xDFFF (Surrogate range)
      # Check if it's a HIGH surrogate (0xD800 - 0xDBFF)
      if cp <= MAX_HIGH_SURROGATE:
        # It's a high surrogate.Peek at the next codepoint.
        if nextI < n: # Use 'n' (end) not 'input.len'
          let (cp2, nextI2) = decodeUtf8(input, nextI)
          
          # Check if next is a LOW surrogate (0xDC00 - 0xDFFF)
          if cp2 >= 0xDC00 and cp2 <= MAX_LOW_SURROGATE:
            # We have a valid pair!
            # Combine them to check for non-characters (e.g., U+1FFFE)
            let combinedCp = 0x10000 + ((cp - MIN_HIGH_SURROGATE) shl 10) + (cp2 - 0xDC00)

            if isNonCharacter(combinedCp):
              # Invalid pair (e.g., U+1FFFE).

              return i # Return index of the *start* of the invalid pair
            else:
              # Valid surrogate pair (e.g., U+10000).
              # Pass them through.
              i = nextI2 # Consume both codepoints
              continue # Continue to next loop iteration
        
      # If we're here, it's a high surrogate *without* a following low surrogate.
      # Fall through to the invalid case.
      # This handles:
      # 1. Isolated low surrogates (0xDC00 - 0xDFFF)
      # 2. Isolated high surrogates (fell through from above)
      return i # Invalid surrogate

    elif cp >= 0xFDD0: # Check for non-characters

      if isNonCharacter(cp):
        return i # Invalid non-character
      elif cp <= 0x10FFFF:
        discard # Valid (e.g. 0xFFFD)
      else:
        return i # > 0x10FFFF

    else:
      # All other valid chars (e.g., U+E000 - U+FDCF)
      discard # Valid

    i = nextI # Move to the next codepoint

  return n


method encodeInternal*(encoder: XMLEncoder, input: string, output: var string) =
  ## Encodes the input string by iterating over Runes (Unicode codepoints)
  var i = 0
  while i < input.len:
    let (cp, nextI) = decodeUtf8(input, i)

    # --- XMLEncoder-specific logic (from XMLEncoder.java) ---

    if cp == int(INVALID_CHARACTER_REPLACEMENT):
        output.add(INVALID_CHARACTER_REPLACEMENT)

    elif cp < DEL: # 0-126
      if (cp > '>'.int) or ((encoder.validMask and (1'u64 shl cp)) != 0):
        output.add(input[i ..< nextI]) # Valid ASCII
      else:
        # Needs encoding or is invalid ASCII control
        case cp:
        of '&'.int: output.add("&amp;")
        of '<'.int: 
          output.add("&lt;")
        of '>'.int: output.add("&gt;")
        of '\''.int: output.add("&#39;")
        of '"'.int: output.add("&#34;")
        else:       output.add(INVALID_CHARACTER_REPLACEMENT) # e.g. \0, \1, etc.

    elif cp < MIN_HIGH_SURROGATE: # 127 - 0xD7FF
      # Java logic: if (ch > Unicode.MAX_C1_CTRL_CHAR || ch == Unicode.NEL)
      if (cp > MAX_C1_CTRL_CHAR or cp == NEL):
        output.add(input[i ..< nextI]) # Valid (e.g., 0xA0)
      else:
        # Invalid C0 control (0x7F) or C1 control (0x80-0x9F, excl 0x85)
        output.add(INVALID_CHARACTER_REPLACEMENT)
        
    elif cp <= MAX_LOW_SURROGATE: # 0xD800 - 0xDFFF (Surrogate range)
      # Check if it's a HIGH surrogate (0xD800 - 0xDBFF)
      if cp <= MAX_HIGH_SURROGATE:
        # It's a high surrogate. Peek at the next codepoint.
        if nextI < input.len:
          let (cp2, nextI2) = decodeUtf8(input, nextI)
          
          # Check if next is a LOW surrogate (0xDC00 - 0xDFFF)
          if cp2 >= 0xDC00 and cp2 <= MAX_LOW_SURROGATE:
            # We have a valid pair!
            # Combine them to check for non-characters (e.g., U+1FFFE)
            # Formula from Java's Character.toCodePoint
            let combinedCp = 0x10000 + ((cp - MIN_HIGH_SURROGATE) shl 10) + (cp2 - 0xDC00)

            if isNonCharacter(combinedCp):
              # Invalid pair (e.g., U+1FFFE). Java replaces the pair with *one* space.
              output.add(INVALID_CHARACTER_REPLACEMENT)
              i = nextI2 # Consume both codepoints
              continue # Continue to next loop iteration
            else:
              # Valid surrogate pair (e.g., U+10000). Pass them through.
              output.add(input[i ..< nextI])  # Add high surrogate bytes
              output.add(input[nextI ..< nextI2]) # Add low surrogate bytes
              i = nextI2
              continue # Continue to next loop iteration
        
        # If we're here, it's a high surrogate *without* a following low surrogate.
        # Fall through to the invalid case.
      
      # This handles:
      # 1. Isolated low surrogates (0xDC00 - 0xDFFF)
      # 2. Isolated high surrogates (fell through from above)
      output.add(INVALID_CHARACTER_REPLACEMENT)

    elif cp >= 0xFDD0: # Check for non-characters

      if isNonCharacter(cp):
        output.add(INVALID_CHARACTER_REPLACEMENT) 
      elif cp <= 0x10FFFF:
        output.add(input[i ..< nextI]) # Valid (e.g. 0xFFFD)
      else:
        output.add(INVALID_CHARACTER_REPLACEMENT) # > 0x10FFFF

    else:
      # All other valid chars (e.g., U+E000 - U+FDCF)
      output.add(input[i ..< nextI])

    i = nextI
