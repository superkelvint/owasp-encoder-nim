# cdataencoder.nim
import encoder
import std/unicode

const
  CDATA_END_ENCODED* = "]]]]><![CDATA[>"
  INVALID_CHARACTER_REPLACEMENT* = ' ' # From XMLEncoder

  # Unicode constants
  NEL = 0x85
  MAX_C1_CTRL_CHAR = 0x9F
  MIN_HIGH_SURROGATE = 0xD800
  MAX_HIGH_SURROGATE = 0xDBFF
  MIN_LOW_SURROGATE = 0xDC00
  MAX_LOW_SURROGATE = 0xDFFF

type
  CDATAEncoder* = ref object of Encoder
    # No special fields needed

proc newCDATAEncoder*(): CDATAEncoder =
  ## Constructor for the CDATAEncoder
  new(result)

# Helper proc to check for XML non-characters
proc isXMLNonCharacter(cp: int): bool =
  return (cp >= 0xFDD0 and cp <= 0xFDEF) or (cp and 0xFFFF) in [0xFFFE, 0xFFFF]

method firstEncodedOffset*(
   encoder: CDATAEncoder, input: string, off: int, len: int
): int =
  ## Port of the Java firstEncodedOffset, using the manual UTF-8 decoder
  let n = off + len
  var i = off
  while i < n:
    let b = input[i].uint8
    let j = i # Save the starting byte offset of this rune

    # --- This is your UTF-8 decoding logic from encodeInternal [cite: 9-16] ---
    let (cp, nextI) =
      if (b and 0x80) == 0:
        (int(b), i + 1)
      elif (b and 0xE0) == 0xC0 and i + 1 < input.len:
        let b2 = input[i + 1].uint8
        if (b2 and 0xC0) == 0x80:
          (((b and 0x1F).int shl 6) or (b2 and 0x3F).int, i + 2)
        else:
          (int(INVALID_CHARACTER_REPLACEMENT), i + 1) # Invalid sequence
      elif (b and 0xF0) == 0xE0 and i + 2 < input.len:
        let b2 = input[i + 1].uint8
        let b3 = input[i + 2].uint8
        if (b2 and 0xC0) == 0x80 and (b3 and 0xC0) == 0x80:
          (((b and 0x0F).int shl 12) or ((b2 and 0x3F).int shl 6) or (b3 and 0x3F).int, i + 3)
        else:
          (int(INVALID_CHARACTER_REPLACEMENT), i + 1) # Invalid sequence
      elif (b and 0xF8) == 0xF0 and i + 3 < input.len:
        let b2 = input[i + 1].uint8
        let b3 = input[i + 2].uint8
        let b4 = input[i + 3].uint8
        if (b2 and 0xC0) == 0x80 and (b3 and 0xC0) == 0x80 and (b4 and 0xC0) == 0x80:
          (((b and 0x07).int shl 18) or ((b2 and 0x3F).int shl 12) or
            ((b3 and 0x3F).int shl 6) or (b4 and 0x3F).int, i + 4)
        else:
          (int(INVALID_CHARACTER_REPLACEMENT), i + 1) # Invalid sequence
      else:
        (int(INVALID_CHARACTER_REPLACEMENT), i + 1) # Invalid start byte

    # --- This is the validation logic, now running on correct codepoints ---
    
    if cp == int(INVALID_CHARACTER_REPLACEMENT):
      return j # Bad UTF-8 sequence

    # 1. Check for ']' (the only special char in CDATA)
    if cp == ']'.int:
      if nextI < n and input[nextI] == ']':
        # Found "]]"
        var k = nextI + 1
        while k < n and input[k] == ']':
          inc k
        
        if k < n and input[k] == '>':
          # Found "]]...>"
          return j # Return the start of the *first* ']'
      # else: Just a single ']' or "]]" not followed by '>', which is fine.

    # 2. Check for invalid XML control chars (C0)
    elif (cp < ' '.int and cp != '\t'.int and cp != '\n'.int and cp != '\r'.int):
      return j # Invalid C0 control char
    
    # 3. Check for 0x7F (DEL) and C1 control chars
    elif (cp >= 0x7F and cp <= MAX_C1_CTRL_CHAR and cp != NEL):
      return j # <--- THIS IS THE FIX. It now catches 0x7F.
    
    # 4. Check for surrogates
    elif (cp >= MIN_HIGH_SURROGATE and cp <= MAX_LOW_SURROGATE):
      return j # Isolated surrogate
    
    # 5. Check for non-characters and out-of-range
    elif cp > 0x10FFFF or isXMLNonCharacter(cp):
      return j # Invalid non-character range
    
    # Valid char, continue to the next one
    i = nextI
  
  return n # All chars were valid

method encodeInternal*(encoder: CDATAEncoder, input: string, output: var string) =
  ## Encodes the input string by iterating over Runes (Unicode codepoints)
  var i = 0
  while i < input.len:
    let b = input[i].uint8

    # --- UTF-8 decoding ---
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

    # --- CDATAEncoder logic ---

    # 1. Check for invalid XML chars (same as XMLCommentEncoder)
    if cp == int(INVALID_CHARACTER_REPLACEMENT) or
       (cp < ' '.int and cp != '\t'.int and cp != '\n'.int and cp != '\r'.int) or
       (cp >= 0x7F and cp <= MAX_C1_CTRL_CHAR and cp != NEL) or
       (cp >= MIN_HIGH_SURROGATE and cp <= MAX_LOW_SURROGATE) or
       isXMLNonCharacter(cp) or
       cp > 0x10FFFF:
      
      output.add(INVALID_CHARACTER_REPLACEMENT)
      i = nextI
      continue

    # 2. Check for ']' (which is single-byte ASCII)
    if cp == ']'.int:
      if i + 2 < input.len and input[i+1] == ']' and input[i+2] == '>':
        # Found "]]>"
        output.add(CDATA_END_ENCODED)
        i += 3 # Skip all 3 bytes
      else:
        # Just a "]" or "]]" not followed by ">"
        output.add(']')
        i = nextI
    else:
      # Not ']' and not invalid.
      output.add(input[i ..< nextI])
      i = nextI