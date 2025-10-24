# xmlcommentencoder.nim
import encoder
import std/unicode

const
  HYPHEN_REPLACEMENT* = '~'
  INVALID_CHARACTER_REPLACEMENT* = '?' # From XMLEncoder

  # Unicode constants
  DEL = 0x7F
  NEL = 0x85
  MAX_C1_CTRL_CHAR = 0x9F
  MIN_HIGH_SURROGATE = 0xD800
  MAX_HIGH_SURROGATE = 0xDBFF
  MIN_LOW_SURROGATE = 0xDC00
  MAX_LOW_SURROGATE = 0xDFFF

type
  XMLCommentEncoder* = ref object of Encoder
    # No special fields needed

proc newXMLCommentEncoder*(): XMLCommentEncoder =
  ## Constructor for the XMLCommentEncoder
  new(result)

# Helper proc to check for XML non-characters
proc isXMLNonCharacter(cp: int): bool =
  return (cp >= 0xFDD0 and cp <= 0xFDEF) or (cp and 0xFFFF) in [0xFFFE, 0xFFFF]

method firstEncodedOffset*(
    encoder: XMLCommentEncoder, input: string, off: int, len: int
): int =
  ## Finds the byte offset of the first character that needs encoding.
  ## This version correctly decodes UTF-8 codepoints AND handles hyphens.
  let n = off + len
  var i = off
  while i < n:
    let b = input[i].uint8
    let currentByteOffset = i # Start byte of the current codepoint

    # --- UTF-8 decoding, adapted from encodeInternal ---
    let (cp, nextI) =
      if (b and 0x80) == 0:
        (int(b), i + 1)
      elif (b and 0xE0) == 0xC0 and i + 1 < n:
        let b2 = input[i + 1].uint8
        if (b2 and 0xC0) == 0x80:
          (((b and 0x1F).int shl 6) or (b2 and 0x3F).int, i + 2)
        else:
          (int(INVALID_CHARACTER_REPLACEMENT), i + 1) # Invalid sequence
      elif (b and 0xF0) == 0xE0 and i + 2 < n:
        let b2 = input[i + 1].uint8
        let b3 = input[i + 2].uint8
        if (b2 and 0xC0) == 0x80 and (b3 and 0xC0) == 0x80:
          (((b and 0x0F).int shl 12) or ((b2 and 0x3F).int shl 6) or (b3 and 0x3F).int, i + 3)
        else:
          (int(INVALID_CHARACTER_REPLACEMENT), i + 1) # Invalid sequence
      elif (b and 0xF8) == 0xF0 and i + 3 < n:
        let b2 = input[i + 1].uint8
        let b3 = input[i + 2].uint8
        let b4 = input[i + 3].uint8
        if (b2 and 0xC0) == 0x80 and (b3 and 0xC0) == 0x80 and (b4 and 0xC0) == 0x80:
          (((b and 0x07).int shl 18) or ((b2 and 0x3F).int shl 12) or
            ((b3 and 0x3F).int shl 6) or (b4 and 0x3F).int, i + 4)
        else:
          (int(INVALID_CHARACTER_REPLACEMENT), i + 1) # Invalid sequence
      else:
        (int(INVALID_CHARACTER_REPLACEMENT), i + 1) # Invalid sequence

    # --- Validation logic, using the decoded 'cp' ---

    # 1. Handle special '-' logic
    if cp == '-'.int:
      if nextI >= n: # This is the last char in the string
        return currentByteOffset # Trailing '-' needs encoding
      elif input[nextI] == '-': # Lookahead finds "--"
        return currentByteOffset # Start of "--" needs encoding
      # else: just a normal hyphen, which is valid. Do nothing.
      # This fixes the optimization bug.

    # 2. Handle invalid XML chars (logic from XMLEncoder)
    elif cp == int(INVALID_CHARACTER_REPLACEMENT):
      return currentByteOffset # Malformed UTF-8
    elif cp < DEL: # ASCII (0-126), but not '-'
      if not ((cp >= ' '.int) or (cp == '\t'.int) or (cp == '\n'.int) or (cp == '\r'.int)):
        return currentByteOffset # Invalid control char
      # else: valid ASCII, continue
    elif cp == DEL: # 127 - 0xD7FF
      return currentByteOffset
    elif cp < MIN_HIGH_SURROGATE: # 127 - 0xD7FF
      if (cp >= 0x80 and cp <= MAX_C1_CTRL_CHAR) and cp != NEL:
        return currentByteOffset # C1 control (This fixes the À bug)
      # else: valid (like our À), continue
    elif cp <= MAX_LOW_SURROGATE: # 0xD800 - 0xDFFF
      return currentByteOffset # Isolated surrogate
    elif isXMLNonCharacter(cp):
      return currentByteOffset
    elif cp > 0x10FFFF:
      return currentByteOffset # Out of Unicode range
    
    # If we get here, the codepoint is valid.
    i = nextI # Move to the next codepoint
    
  return n # No encoded chars found

method encodeInternal*(encoder: XMLCommentEncoder, input: string, output: var string) =
  ## Encodes the input string by iterating over Runes (Unicode codepoints)
  var i = 0
  while i < input.len:
    let b = input[i].uint8

    # --- UTF-8 decoding, adapted from xmlencoder.nim ---
    let (cp, nextI) =
      if (b and 0x80) == 0:
        (int(b), i + 1)
      elif (b and 0xE0) == 0xC0 and i + 1 < input.len:
        let b2 = input[i + 1].uint8
        if (b2 and 0xC0) == 0x80:
          (((b and 0x1F).int shl 6) or (b2 and 0x3F).int, i + 2)
        else:
          (int(INVALID_CHARACTER_REPLACEMENT), i + 1)
      elif (b and 0xF0) == 0xE0 and i + 2 < input.len:
        let b2 = input[i + 1].uint8
        let b3 = input[i + 2].uint8
        if (b2 and 0xC0) == 0x80 and (b3 and 0xC0) == 0x80:
          (((b and 0x0F).int shl 12) or ((b2 and 0x3F).int shl 6) or (b3 and 0x3F).int, i + 3)
        else:
          (int(INVALID_CHARACTER_REPLACEMENT), i + 1)
      elif (b and 0xF8) == 0xF0 and i + 3 < input.len:
        let b2 = input[i + 1].uint8
        let b3 = input[i + 2].uint8
        let b4 = input[i + 3].uint8
        if (b2 and 0xC0) == 0x80 and (b3 and 0xC0) == 0x80 and (b4 and 0xC0) == 0x80:
          (((b and 0x07).int shl 18) or ((b2 and 0x3F).int shl 12) or
            ((b3 and 0x3F).int shl 6) or (b4 and 0x3F).int, i + 4)
        else:
          (int(INVALID_CHARACTER_REPLACEMENT), i + 1)
      else:
        (int(INVALID_CHARACTER_REPLACEMENT), i + 1)

    # --- XMLCommentEncoder-specific logic ---

    # 1. Handle special '-' logic
    if cp == '-'.int:
      if nextI >= input.len: # This is the last char in the string
        output.add(HYPHEN_REPLACEMENT)
      elif input[nextI] == '-': # Lookahead finds "--"
        output.add('-')
        output.add(HYPHEN_REPLACEMENT)
        i = nextI + 1 # Advance past the *second* hyphen
        continue      # Continue to next while-loop iteration
      else: # Just a normal hyphen
        output.add('-')

    # 2. Handle invalid XML chars (logic from XMLEncoder)
    elif cp == int(INVALID_CHARACTER_REPLACEMENT):
      output.add(INVALID_CHARACTER_REPLACEMENT)
    elif cp < DEL: # ASCII (0-126), but not '-'
      if (cp >= ' '.int) or (cp == '\t'.int) or (cp == '\n'.int) or (cp == '\r'.int):
        output.add(input[i ..< nextI]) # Valid ASCII
      else:
        output.add(INVALID_CHARACTER_REPLACEMENT) # Invalid control char
    elif cp == DEL: # 127 - 0xD7FF
      output.add(INVALID_CHARACTER_REPLACEMENT)
    elif cp < MIN_HIGH_SURROGATE: # 127 - 0xD7FF
      if (cp >= 0x80 and cp <= MAX_C1_CTRL_CHAR) and cp != NEL:
        output.add(INVALID_CHARACTER_REPLACEMENT) # C1 control
      else:
        output.add(input[i ..< nextI]) # Valid
    elif cp <= MAX_LOW_SURROGATE: # 0xD800 - 0xDFFF
      output.add(INVALID_CHARACTER_REPLACEMENT) # Isolated surrogate
    elif isXMLNonCharacter(cp):
      output.add(INVALID_CHARACTER_REPLACEMENT)
    elif cp > 0x10FFFF:
      output.add(INVALID_CHARACTER_REPLACEMENT) # Out of Unicode range
    else:
      # All other valid chars (e.g., 0xE000-0xFDCF, 0xFFFD, etc.)
      output.add(input[i ..< nextI])

    i = nextI