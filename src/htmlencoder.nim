# htmlencoder.nim
import encoder

const
  # This is the replacement char used in the Java default case
  INVALID_CHARACTER_REPLACEMENT* = '-'

  # Unicode constants
  NEL = 0x85
  MAX_C1_CTRL_CHAR = 0x9F
  MIN_HIGH_SURROGATE = 0xD800
  MAX_HIGH_SURROGATE = 0xDBFF
  MIN_LOW_SURROGATE = 0xDC00
  MAX_LOW_SURROGATE = 0xDFFF
  LINE_SEPARATOR = 0x2028
  PARAGRAPH_SEPARATOR = 0x2029

type
  HTMLEncoder* = ref object of Encoder
    # No special fields needed

proc newHTMLEncoder*(): HTMLEncoder =
  ## Constructor for the HTMLEncoder
  new(result)

# Helper proc to check for XML/HTML non-characters
proc isNonCharacter(cp: int): bool =
  return (cp >= 0xFDD0 and cp <= 0xFDEF) or (cp and 0xFFFF) in [0xFFFE, 0xFFFF]

# Helper proc to numerically encode a codepoint
proc encodeNumeric(cp: int): string =
  result = "&#" & $cp & ";"

method firstEncodedOffset*(
    encoder: HTMLEncoder, input: string, off: int, len: int
): int =
  ## Port of the Java firstEncodedOffset, fixed to handle UTF-8
  let n = off + len
  var i = off
  while i < n:
    # --- UTF-8 decoding (based on encodeInternal) ---
    let b = input[i].uint8  # <-- MOVED THIS LINE
    # We use -1 to mean "invalid" to distinguish from any valid codepoint
    let (cp, nextI) =       # <-- TUPLE ASSIGNMENT
      if (b and 0x80) == 0: # <-- NOW STARTS WITH AN EXPRESSION
        (int(b), i + 1)
      elif (b and 0xE0) == 0xC0 and i + 1 < n: # Use 'n'
        let b2 = input[i + 1].uint8
        if (b2 and 0xC0) == 0x80:
          (((b and 0x1F).int shl 6) or (b2 and 0x3F).int, i + 2)
        else:
          (-1, i + 1) # Invalid sequence
      elif (b and 0xF0) == 0xE0 and i + 2 < n: # Use 'n'
        let b2 = input[i + 1].uint8
        let b3 = input[i + 2].uint8
        if (b2 and 0xC0) == 0x80 and (b3 and 0xC0) == 0x80:
          (((b and 0x0F).int shl 12) or ((b2 and 0x3F).int shl 6) or (b3 and 0x3F).int, i + 3)
        else:
          (-1, i + 1) # Invalid sequence
      elif (b and 0xF8) == 0xF0 and i + 3 < n: # Use 'n'
        let b2 = input[i + 1].uint8
        let b3 = input[i + 2].uint8
        let b4 = input[i + 3].uint8
        if (b2 and 0xC0) == 0x80 and (b3 and 0xC0) == 0x80 and (b4 and 0xC0) == 0x80:
          (((b and 0x07).int shl 18) or ((b2 and 0x3F).int shl 12) or
            ((b3 and 0x3F).int shl 6) or (b4 and 0x3F).int, i + 4)
        else:
          (-1, i + 1) # Invalid sequence
      else:
        (-1, i + 1) # Invalid start byte

    if cp == -1: # Invalid UTF-8 sequence
      return i

    # --- HTMLEncoder-specific logic (from Java) ---
    case cp
    of '\t'.int, '\r'.int, '\f'.int, '\n'.int, ' '.int, '"'.int, '\''.int,
       '/'.int, '='.int, '`'.int, '&'.int, '<'.int, '>'.int:
      return i # Needs encoding
    
    # Valid ASCII chars (with the '"' bug fixed)
    of '!'.int, '#'.int .. '%'.int, '('.int .. '.'.int, '0'.int .. ':'.int, ';'.int, '?'.int .. 'Z'.int,
       '['.int .. '^'.int, '_'.int, 'a'.int .. 'z'.int, '{'.int .. '~'.int:
      i = nextI # Continue

    else:
      # Check non-ASCII and other control chars
      if cp == NEL or cp == LINE_SEPARATOR or cp == PARAGRAPH_SEPARATOR:
        return i # Needs encoding

      # Check for invalid codepoints
      if (cp <= MAX_C1_CTRL_CHAR and cp != NEL) or # 0-31 and 127-159 (excl NEL)
         (cp >= MIN_HIGH_SURROGATE and cp <= MAX_LOW_SURROGATE) or # Surrogates
         (cp > 0x10FFFF) or # Outside valid Unicode
         (isNonCharacter(cp)): # Non-chars
        return i # Invalid char
      
      # Otherwise, it's a valid non-ASCII char
      i = nextI

  return n

method encodeInternal*(encoder: HTMLEncoder, input: string, output: var string) =
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

    # --- HTMLEncoder-specific logic ---

    if cp == int(INVALID_CHARACTER_REPLACEMENT):
      output.add(INVALID_CHARACTER_REPLACEMENT)
      i = nextI
      continue

    var wasEncodedOrInvalid = false
    case cp
    of '\t'.int:
      output.add("&#9;")
      wasEncodedOrInvalid = true
    of '\r'.int, '\n'.int, '\f'.int, ' '.int, '"'.int, '\''.int, '/'.int, '='.int, '`'.int:
      output.add(encodeNumeric(cp))
      wasEncodedOrInvalid = true
    of '&'.int:
      output.add("&amp;")
      wasEncodedOrInvalid = true
    of '<'.int:
      output.add("&lt;")
      wasEncodedOrInvalid = true
    of '>'.int:
      output.add("&gt;")
      wasEncodedOrInvalid = true

    # Valid ASCII chars that pass through
    of '!'.int, '#'.int .. '%'.int, '('.int .. '.'.int, '0'.int .. ':'.int, ';'.int, '?'.int .. 'Z'.int,
       '['.int .. '^'.int, '_'.int, 'a'.int .. 'z'.int, '{'.int .. '~'.int:
      discard # Valid, will be added below

    else:
      # Handle non-ASCII and invalid ASCII control chars
      var isInvalid = false
      
      if (cp <= ' '.int) or # 0-31, except 9,10,12,13 handled above
         (cp >= 0x7F and cp <= MAX_C1_CTRL_CHAR and cp != NEL) or # 127-159 (except 133)
         (cp >= MIN_HIGH_SURROGATE and cp <= MAX_LOW_SURROGATE) or
         (isNonCharacter(cp)) or
         (cp > 0x10FFFF):
        isInvalid = true
      
      if isInvalid:
        output.add(INVALID_CHARACTER_REPLACEMENT)
        wasEncodedOrInvalid = true
      elif cp == NEL or cp == LINE_SEPARATOR or cp == PARAGRAPH_SEPARATOR:
        output.add(encodeNumeric(cp))
        wasEncodedOrInvalid = true
      # else: valid non-ASCII, will be added below

    if not wasEncodedOrInvalid:
      output.add(input[i ..< nextI])

    i = nextI