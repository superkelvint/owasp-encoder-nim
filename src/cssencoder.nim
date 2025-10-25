# cssencoder.nim
import encoder
import std/strutils
import std/unicode # ADDED: For Rune functions

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

# Helper proc to write hex (mimics Java's direct array write)
proc writeHex*(output: var string, cp: int) =
  # Use a fixed size for the temporary hex representation (e.g., 6 digits for max Unicode)
  # NOTE: The simplest, fastest, and lowest-level way in Nim is often to rely on 
  # strutils.toHex and then manually writing the result, but since that was the issue, 
  # we must use manual char calculation or a custom template.
  
  # Since we cannot rely on toHex, we write directly to simulate array assignment.
  
  const maxDigits = 6
  var temp: array[maxDigits, char]
  var p = maxDigits - 1
  var val = cp

  if val == 0:
    # Special case for U+0000
    output.add('0')
    return

  while val > 0 and p >= 0:
    temp[p] = LHEX[val and HEX_MASK]
    val = val shr HEX_SHIFT
    p -= 1
    
  # Find the start of the hex string (skip leading zeros, but always output at least one char)
  var start = p + 1
  
  for j in start ..< maxDigits:
    output.add(temp[j])

method firstEncodedOffset*(
    encoder: CSSEncoder, input: string, off: int, len: int
): int =
  ## Finds the first ASCII character position that needs encoding.
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
    if cp <= 127:
      return i # ASCII char that needs encoding
    
    # This part handles non-ASCII ranges that must be encoded (128-159 and separators)
    # The original Java logic allows non-encoded non-ASCII, but the fast path must return
    # to the main loop for multi-byte decoding.
    if cp > 159 and cp < LINE_SEPARATOR or cp > PARAGRAPH_SEPARATOR:
      if cp < MIN_HIGH_SURROGATE or cp > MAX_LOW_SURROGATE:
        # Valid non-ascii. We must bail to `encodeInternal` to handle UTF-8 sequences.
        return i 

    # If we are here, it's a non-ASCII char that needs encoding.
    return i

  return n

method encodeInternal*(encoder: CSSEncoder, input: string, output: var string) =
  ## Encodes the input string by iterating over Runes (Unicode codepoints) using Safe Chunking.
  var i = 0
  var lastSafe = 0 # TRACKER: Start of the current safe chunk
  
  while i < input.len:
    let charLen = runeLenAt(input, i) # REPLACED: manual UTF-8 decoding
    let cpRune = input.runeAt(i)       # REPLACED: manual UTF-8 decoding
    let cp = cpRune.int
    let nextI = i + charLen

    # --- INVALID UTF-8 HANDLING ---
    if charLen == 0:
        if i > lastSafe: output.add(input[lastSafe ..< i])
        output.add(INVALID_REPLACEMENT_CHARACTER)
        i = i + 1 
        lastSafe = i
        continue

    var needsEncoding = false
    var isInvalid = false
    
    # --- CSSEncoder-specific logic (from CSSEncoder.java) ---
    
    if cp >= MIN_HIGH_SURROGATE and cp <= MAX_LOW_SURROGATE:
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
      # This covers: 0-127 not in masks, 128-159, LINE_SEPARATOR, PARAGRAPH_SEPARATOR
      needsEncoding = true
    
    # --- OUTPUT LOGIC (Safe Chunking) ---

    if isInvalid:
      # FLUSH: Emit preceding safe chunk
      if i > lastSafe: output.add(input[lastSafe ..< i])
      output.add(INVALID_REPLACEMENT_CHARACTER)
      lastSafe = nextI
    elif needsEncoding:
      # FLUSH: Emit preceding safe chunk
      if i > lastSafe: output.add(input[lastSafe ..< i])
      
      # --- Hex-escape logic from CSSEncoder.java ---
      var needsSpace = false
      if nextI < input.len:
        let la = input[nextI] # Lookahead character
        if (la >= '0' and la <= '9') or
           (la >= 'a' and la <= 'f') or
           (la >= 'A' and la <= 'F') or
           la == ' ' or la == '\n' or la == '\r' or la == '\t' or la == '\f':
          needsSpace = true

      # ADD THE ESCAPE (Direct Writes)
      output.add('\\')
      writeHex(output, cp) # Optimized hex writing
      
      if needsSpace:
        output.add(' ')
        
      lastSafe = nextI
    else:
      # Valid character, no encoding needed - continue to extend safe chunk
      discard

    i = nextI
    
  # FINAL FLUSH: Copy the final safe chunk
  if input.len > lastSafe:
    output.add(input[lastSafe ..< input.len])