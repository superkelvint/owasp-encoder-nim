# uriencoder.nim
import encoder

const
  UHEX: array[16, char] =
    ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F']

  # RFC 3986 Unreserved Characters
  CHARS_0_TO_9 = 10
  CHARS_A_TO_Z = 26
  LONG_BITS = 64 # for 64-bit masks

  UNRESERVED_MASK_LOW =
    ((1'u64 shl CHARS_0_TO_9) - 1) shl '0'.int or (1'u64 shl '-'.int) or
    (1'u64 shl '.'.int)

  UNRESERVED_MASK_HIGH =
    ((1'u64 shl CHARS_A_TO_Z) - 1) shl ('a'.int - LONG_BITS) or
    ((1'u64 shl CHARS_A_TO_Z) - 1) shl ('A'.int - LONG_BITS) or
    (1'u64 shl ('_'.int - LONG_BITS)) or (1'u64 shl ('~'.int - LONG_BITS))

  # RFC 3986 Reserved Characters
  RESERVED_MASK_LOW =
    (1'u64 shl ':'.int) or (1'u64 shl '/'.int) or (1'u64 shl '?'.int) or
    (1'u64 shl '#'.int) or (1'u64 shl '!'.int) or (1'u64 shl '$'.int) or
    (1'u64 shl '&'.int) or (1'u64 shl '\''.int) or (1'u64 shl '('.int) or
    (1'u64 shl ')'.int) or (1'u64 shl '*'.int) or (1'u64 shl '+'.int) or
    (1'u64 shl ','.int) or (1'u64 shl ';'.int) or (1'u64 shl '='.int)

  RESERVED_MASK_HIGH =
    (1'u64 shl ('['.int - LONG_BITS)) or (1'u64 shl (']'.int - LONG_BITS)) or
    (1'u64 shl ('@'.int - LONG_BITS))

  # UTF-8 constants
  MAX_UTF8_2_BYTE = 0x7ff
  UTF8_2_BYTE_FIRST_MSB = 0xc0
  UTF8_3_BYTE_FIRST_MSB = 0xe0
  UTF8_4_BYTE_FIRST_MSB = 0xf0
  UTF8_BYTE_MSB = 0x80
  UTF8_SHIFT = 6
  UTF8_MASK = 0x3f

  HEX_SHIFT = 4
  HEX_MASK = 0x0F

  INVALID_REPLACEMENT_CHARACTER = '-'

type
  URIEncoderMode* = enum
    COMPONENT
    FULL_URI

  URIEncoder* = ref object of Encoder
    lowMask: uint64
    highMask: uint64
    mode: URIEncoderMode

proc newURIEncoder*(mode: URIEncoderMode): URIEncoder =
  ## Constructor for the URIEncoder
  new(result)
  result.mode = mode
  case mode
  of COMPONENT:
    result.lowMask = UNRESERVED_MASK_LOW
    result.highMask = UNRESERVED_MASK_HIGH
  of FULL_URI:
    result.lowMask = UNRESERVED_MASK_LOW or RESERVED_MASK_LOW
    result.highMask = UNRESERVED_MASK_HIGH or RESERVED_MASK_HIGH

# Helper to percent-encode a single byte
proc addPercentEncoded(output: var string, b: int) =
  output.add('%')
  output.add(UHEX[b shr HEX_SHIFT])
  output.add(UHEX[b and HEX_MASK])

# Helper to check if a codepoint needs encoding
proc needsEncoding(encoder: URIEncoder, cp: int): bool =
  if cp <= 127: # ASCII fast path
    if cp < LONG_BITS:
      return (encoder.lowMask and (1'u64 shl cp)) == 0
    else:
      return (encoder.highMask and (1'u64 shl (cp - LONG_BITS))) == 0
  else:
    # Non-ASCII always needs encoding
    return true

method firstEncodedOffset*(
    encoder: URIEncoder, input: string, off: int, len: int
): int =
  let n = off + len
  var i = off
  while i < n:
    let ch = input[i]
    if ord(ch) <= 127: # ASCII fast path
      if not encoder.needsEncoding(ord(ch)):
        inc i
      else:
        return i
    else:
      # Non-ASCII UTF-8 sequence starts here
      return i
  return n

method encodeInternal*(encoder: URIEncoder, input: string, output: var string) =
  ## Encodes the input string by iterating over Runes (Unicode codepoints)
  var i = 0
  var lastSafe = 0 # TRACKER: Start of the current safe chunk

  while i < input.len:
    # --- INSERT MINIMALIST FAST PATH HERE ---
    var fastI = i
    while fastI < input.len:
      let ch = input[fastI]
      let cp = ord(ch)
      
      # Skip only characters that are guaranteed safe and are ASCII
      # This fast path must only skip single-byte, unreserved characters.
      # The UNRESERVED_MASK logic covers 'a'-'z', 'A'-'Z', '0'-'9', '-', '.', '_', '~'
      # which are the safest. We check the masks for a fast, safe skip.
      if cp <= 127 and (
        (cp < LONG_BITS and (encoder.lowMask and (1'u64 shl cp)) != 0) or
        (cp >= LONG_BITS and (encoder.highMask and (1'u64 shl (cp - LONG_BITS))) != 0)
      ):
        fastI += 1
      else:
        break
        
    # FLUSH: Copy the safe chunk found by the Fast Path
    if fastI > i:
      if i > lastSafe: # Flush any preceding Rune safe chunk (shouldn't happen here, but safe)
        output.add(input[lastSafe ..< i]) 
      output.add(input[i ..< fastI]) # Copy the new ASCII safe chunk
      lastSafe = fastI
      i = fastI
      continue # Continue to next iteration
    # ----------------------------------------
    
    # Original Rune processing logic starts here
    let b = input[i].uint8
    
    # Determine how many bytes this UTF-8 sequence contains
    let (cp, nextI) =
      if (b and 0x80) == 0:
        # 1-byte ASCII (0xxxxxxx)
        (int(b), i + 1)
      elif (b and 0xE0) == 0xC0 and i + 1 < input.len:
        # 2-byte UTF-8 (110xxxxx 10xxxxxx)
        let b2 = input[i + 1].uint8
        if (b2 and 0xC0) == 0x80:
          (((b and 0x1F).int shl 6) or (b2 and 0x3F).int, i + 2)
        else:
          (int(INVALID_REPLACEMENT_CHARACTER), i + 1) # Invalid continuation
      elif (b and 0xF0) == 0xE0 and i + 2 < input.len:
        # 3-byte UTF-8 (1110xxxx 10xxxxxx 10xxxxxx)
        let b2 = input[i + 1].uint8
        let b3 = input[i + 2].uint8
        if (b2 and 0xC0) == 0x80 and (b3 and 0xC0) == 0x80:
          (
            ((b and 0x0F).int shl 12) or ((b2 and 0x3F).int shl 6) or (b3 and 0x3F).int,
            i + 3,
          )
        else:
          (int(INVALID_REPLACEMENT_CHARACTER), i + 1) # Invalid continuation
      elif (b and 0xF8) == 0xF0 and i + 3 < input.len:
        # 4-byte UTF-8 (11110xxx 10xxxxxx 10xxxxxx 10xxxxxx)
        let b2 = input[i + 1].uint8
        let b3 = input[i + 2].uint8
        let b4 = input[i + 3].uint8
        if (b2 and 0xC0) == 0x80 and (b3 and 0xC0) == 0x80 and (b4 and 0xC0) == 0x80:
          (
            ((b and 0x07).int shl 18) or ((b2 and 0x3F).int shl 12) or
              ((b3 and 0x3F).int shl 6) or (b4 and 0x3F).int,
            i + 4,
          )
        else:
          (int(INVALID_REPLACEMENT_CHARACTER), i + 1) # Invalid continuation
      else:
        # Invalid UTF-8 sequence or incomplete multibyte at end
        (int(INVALID_REPLACEMENT_CHARACTER), i + 1)

    # Now encode the codepoint
    # Check for invalid codepoints (surrogates or replacement char)
    if cp == int(INVALID_REPLACEMENT_CHARACTER) or (cp >= 0xD800 and cp <= 0xDFFF):
      # FLUSH: Copy the preceding safe chunk
      if i > lastSafe:
        output.add(input[lastSafe ..< i]) 
      
      output.add(INVALID_REPLACEMENT_CHARACTER)
      lastSafe = nextI # UPDATE tracker
    elif encoder.needsEncoding(cp):
      # FLUSH: Copy the preceding safe chunk
      if i > lastSafe:
        output.add(input[lastSafe ..< i]) 
        
      # Encode as UTF-8 bytes (Using addPercentEncoded which is already direct)
      if cp <= 0x7F:
        # 1-byte
        output.addPercentEncoded(cp)
      elif cp <= 0x7FF:
        # 2-byte
        output.addPercentEncoded((0xC0 or (cp shr 6)))
        output.addPercentEncoded((0x80 or (cp and 0x3F)))
      elif cp <= 0xFFFF:
        # 3-byte
        output.addPercentEncoded((0xE0 or (cp shr 12)))
        output.addPercentEncoded((0x80 or ((cp shr 6) and 0x3F)))
        output.addPercentEncoded((0x80 or (cp and 0x3F)))
      else:
        # 4-byte
        output.addPercentEncoded((0xF0 or (cp shr 18)))
        output.addPercentEncoded((0x80 or ((cp shr 12) and 0x3F)))
        output.addPercentEncoded((0x80 or ((cp shr 6) and 0x3F)))
        output.addPercentEncoded((0x80 or (cp and 0x3F)))
        
      lastSafe = nextI # UPDATE tracker
    else:
      # Valid character, no encoding needed - discard old logic
      # output.add(input[i ..< nextI]) # OLD LOGIC REMOVED
      discard # Character is safe; just advance i

    i = nextI
    
  # FINAL FLUSH: Copy the final safe chunk
  if input.len > lastSafe:
    output.add(input[lastSafe ..< input.len])