# cssencoder.nim
import encoder
import std/strutils

const
  LHEX: array[16, char] =
    ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f']

  LONG_BITS = 64 # for 64-bit masks
  INVALID_REPLACEMENT_CHARACTER* = '_'

  # Unicode constants from Java source
  LINE_SEPARATOR = 0x2028
  PARAGRAPH_SEPARATOR = 0x2029
  MIN_HIGH_SURROGATE = 0xD800
  MAX_HIGH_SURROGATE = 0xDBFF
  MIN_LOW_SURROGATE = 0xDC00
  MAX_LOW_SURROGATE = 0xDFFF

  # Per CSSEncoder.java Mode.STRING:
  # set(' ', '~').clear("\"\'<&/\\>")
  STRING_CLEAR_LOW = (1'u64 shl '"'.int) or (1'u64 shl '\''.int) or
                     (1'u64 shl '&'.int) or (1'u64 shl '/'.int) or
                     (1'u64 shl '<'.int) or (1'u64 shl '>'.int)
  STRING_MASK_LOW = (0xFFFFFFFF'u64 shl 32) and (not STRING_CLEAR_LOW)
  STRING_CLEAR_HIGH = (1'u64 shl ('\\'.int - LONG_BITS))
  STRING_MASK_HIGH = (0x7FFFFFFFFFFFFFFF'u64) and (not STRING_CLEAR_HIGH)

  # Per CSSEncoder.java Mode.URL:
  # set("!#$%").set('*', '[').set(']', '~').clear("/<>")
  URL_SET_LOW1 = (1'u64 shl '!'.int) or (1'u64 shl '#'.int) or
                 (1'u64 shl '$'.int) or (1'u64 shl '%'.int)
  URL_SET_LOW2 = 0x3FFFFF'u64 shl '*'.int # Chars 42 ('*') to 63 ('?')
  URL_CLEAR_LOW = (1'u64 shl '/'.int) or (1'u64 shl '<'.int) or (1'u64 shl '>'.int)
  URL_MASK_LOW = (URL_SET_LOW1 or URL_SET_LOW2) and (not URL_CLEAR_LOW)

  URL_SET_HIGH1 = 0x0FFFFFFF'u64 # Chars 64 ('@') to 91 ('[')
  URL_SET_HIGH2 = 0x3FFFFFFFF'u64 shl (93 - LONG_BITS) # Chars 93 (']') to 126 ('~')
  URL_MASK_HIGH = URL_SET_HIGH1 or URL_SET_HIGH2

  HEX_SHIFT = 4
  HEX_MASK = 0x0F

type
  CSSEncoderMode* = enum
    STRING
    URL

  CSSEncoder* = ref object of Encoder
    lowMask: uint64
    highMask: uint64
    mode: CSSEncoderMode

proc newCSSEncoder*(mode: CSSEncoderMode): CSSEncoder =
  ## Constructor for the CSSEncoder
  new(result)
  result.mode = mode
  case mode
  of STRING:
    result.lowMask = STRING_MASK_LOW
    result.highMask = STRING_MASK_HIGH
  of URL:
    result.lowMask = URL_MASK_LOW
    result.highMask = URL_MASK_HIGH

method firstEncodedOffset*(
    encoder: CSSEncoder, input: string, off: int, len: int
): int =
  ## Finds the first ASCII character position that needs encoding.
  ## Bails on the first non-ASCII char, letting encodeInternal handle it.
  let n = off + len
  var i = off
  while i < n:
    let cp = input[i].int
    if cp > 127: # Non-ASCII, let encodeInternal handle
      return i

    if cp < LONG_BITS:
      if (encoder.lowMask and (1'u64 shl cp)) != 0:
        inc i
        continue
    else: # cp is 64..127
      if (encoder.highMask and (1'u64 shl (cp - LONG_BITS))) != 0:
        inc i
        continue

    # If we're here, cp is 0..127 but not in the valid mask
    # or it's a non-ASCII char (>127) that is not allowed.
    # The Java source logic for non-ASCII is complex (allows > 237 etc)
    # but for the ASCII-only fast path, this is correct.
    # Wait, the Java check is `ch > '\237'` (159).
    # Chars 0-127 are either in the mask or not.
    if cp <= 127:
      return i # ASCII char that needs encoding
    
    # This part handles 128-159 and 2028, 2029
    if cp > 159 and cp < LINE_SEPARATOR or cp > PARAGRAPH_SEPARATOR:
      if cp < MIN_HIGH_SURROGATE or cp > MAX_LOW_SURROGATE:
        # Valid non-ascii, but this is the *fast path*.
        # We must bail to `encodeInternal` to handle UTF-8 sequences.
        return i 

    # If we are here, it's a non-ASCII char that needs encoding.
    # (e.g., 128-159, or 2028, 2029, or surrogates)
    # We bail to encodeInternal to handle the full UTF-8 char.
    return i

  return n

method encodeInternal*(encoder: CSSEncoder, input: string, output: var string) =
  ## Encodes the input string by iterating over Runes (Unicode codepoints)
  var i = 0
  while i < input.len:
    let b = input[i].uint8

    # --- UTF-8 decoding, adapted from uriencoder.nim ---
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

    # --- CSSEncoder-specific logic (from CSSEncoder.java) ---

    var needsEncoding = false
    var isInvalid = false

    if cp == int(INVALID_REPLACEMENT_CHARACTER) or (cp >= MIN_HIGH_SURROGATE and cp <= MAX_LOW_SURROGATE):
      isInvalid = true
    elif cp < (2 * LONG_BITS): # ASCII
      if cp < LONG_BITS:
        if (encoder.lowMask and (1'u64 shl cp)) == 0: needsEncoding = true
      else:
        if (encoder.highMask and (1'u64 shl (cp - LONG_BITS))) == 0: needsEncoding = true
    elif cp > 159 and cp < LINE_SEPARATOR or cp > PARAGRAPH_SEPARATOR:
      # This is "nonascii" and is valid, no encoding needed.
      needsEncoding = false
    else:
      # Needs encoding. This covers:
      # - 0-127 not in masks
      # - 128-159 (which are not in "nonascii" range)
      # - LINE_SEPARATOR and PARAGRAPH_SEPARATOR
      needsEncoding = true

    if isInvalid:
      output.add(INVALID_REPLACEMENT_CHARACTER)
    elif needsEncoding:
      # --- Hex-escape logic from CSSEncoder.java ---
      var needsSpace = false
      if nextI < input.len:
        let la = input[nextI] # Lookahead character
        if (la >= '0' and la <= '9') or
           (la >= 'a' and la <= 'f') or
           (la >= 'A' and la <= 'F') or
           la == ' ' or la == '\n' or la == '\r' or la == '\t' or la == '\f':
          needsSpace = true

      # Add the hex escape
      output.add('\\')

      # Convert codepoint to hex string
      # (Using strutils.toHex is simpler than the Java backwards-write)
      if cp == 0:
        output.add('0')
      else:
        var hexStr = toHex(cp).toLowerAscii()
        # Remove leading zeros from the hex string
        var j = 0
        while j < hexStr.len - 1 and hexStr[j] == '0':
          inc j
        output.add(hexStr[j..^1])

      if needsSpace:
        output.add(' ')
    else:
      # Valid character, no encoding needed - add it as-is
      output.add(input[i ..< nextI])

    i = nextI