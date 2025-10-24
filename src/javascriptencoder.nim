# javascriptencoder.nim
import encoder
import std/unicode
import std/strutils
import std/strformat

const
  HEX: array[16, char] =
    ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F']
  HEX_SHIFT = 4
  HEX_MASK = 0x0F
  DEL = 0x7F
  LINE_SEPARATOR = 0x2028
  PARAGRAPH_SEPARATOR = 0x2029

type
  JavaScriptEncoderMode* = enum
    SOURCE    ## Standard encoding, shortest sequence possible
    ATTRIBUTE ## Hex-encodes quotes for HTML attributes
    BLOCK     ## Encodes '/' to prevent breaking </script>
    HTML      ## Both ATTRIBUTE and BLOCK rules combined

  JavaScriptEncoder* = ref object of Encoder
    mode: JavaScriptEncoderMode
    hexEncodeQuotes: bool
    validMasks: array[4, uint32]
    asciiOnly: bool

proc newJavaScriptEncoder*(mode: JavaScriptEncoderMode, asciiOnly: bool): JavaScriptEncoder =
  ## Constructor for the JavaScriptEncoder
  new(result)
  result.mode = mode
  result.asciiOnly = asciiOnly

  # Port of Java's bitmask logic
  # Nim's bitwise ops use full int width, so we use `and 31` for shifts.
  var masks: array[4, uint32] = [
    0'u32,
    0xFFFFFFFF'u32 and not ((1'u32 shl ('\''.int and 31)) or (1'u32 shl ('"'.int and 31))),
    0xFFFFFFFF'u32 and not (1'u32 shl ('\\'.int and 31)),
    if asciiOnly: 0xFFFFFFFF'u32 and not (1'u32 shl (DEL and 31)) else: 0xFFFFFFFF'u32
  ]

  if mode == BLOCK or mode == HTML:
    # Escape '/' and '-'
    masks[1] = masks[1] and not ((1'u32 shl ('/'.int and 31)) or (1'u32 shl ('-'.int and 31)))
  
  if mode != SOURCE:
    masks[1] = masks[1] and not (1'u32 shl ('&'.int and 31))
  
  result.validMasks = masks
  result.hexEncodeQuotes = (mode == ATTRIBUTE or mode == HTML)

method firstEncodedOffset*(
    encoder: JavaScriptEncoder, input: string, off: int, len: int
): int =
  let n = off + len
  var i = off
  while i < n:
    let b = input[i].uint8

    # --- UTF-8 decoding (copied from encodeInternal) ---
    let (cp, nextI) =
      if (b and 0x80) == 0:
        (int(b), i + 1)
      elif (b and 0xE0) == 0xC0 and i + 1 < input.len:
        let b2 = input[i + 1].uint8
        if (b2 and 0xC0) == 0x80:
          (((b and 0x1F).int shl 6) or (b2 and 0x3F).int, i + 2)
        else:
          (-1, i + 1) # Invalid
      elif (b and 0xF0) == 0xE0 and i + 2 < input.len:
        let b2 = input[i + 1].uint8
        let b3 = input[i + 2].uint8
        if (b2 and 0xC0) == 0x80 and (b3 and 0xC0) == 0x80:
          (((b and 0x0F).int shl 12) or ((b2 and 0x3F).int shl 6) or (b3 and 0x3F).int, i + 3)
        else:
          (-1, i + 1)
      elif (b and 0xF8) == 0xF0 and i + 3 < input.len:
        let b2 = input[i + 1].uint8
        let b3 = input[i + 2].uint8
        let b4 = input[i + 3].uint8
        if (b2 and 0xC0) == 0x80 and (b3 and 0xC0) == 0x80 and (b4 and 0xC0) == 0x80:
          (((b and 0x07).int shl 18) or ((b2 and 0x3F).int shl 12) or
            ((b3 and 0x3F).int shl 6) or (b4 and 0x3F).int, i + 4)
        else:
          (-1, i + 1)
      else:
        (-1, i + 1) # Invalid UTF-8
    
    if cp == -1: # Invalid UTF-8, must be "encoded" (passed through)
      return i

    # --- Logic from original firstEncodedOffset ---
    if cp < 128:
      # Check the bitmask
      if (encoder.validMasks[cp shr 5] and (1'u32 shl (cp and 31))) == 0:
        return i
    elif encoder.asciiOnly or cp == LINE_SEPARATOR or cp == PARAGRAPH_SEPARATOR:
      return i # Must be encoded
    
    # Check for surrogates, which are invalid in UTF-8
    if (cp >= 0xD800 and cp <= 0xDFFF):
      return i

    i = nextI # Advance by the number of bytes in the codepoint
  return n

method encodeInternal*(encoder: JavaScriptEncoder, input: string, output: var string) =
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
          (-1, i + 1) # Invalid
      elif (b and 0xF0) == 0xE0 and i + 2 < input.len:
        let b2 = input[i + 1].uint8
        let b3 = input[i + 2].uint8
        if (b2 and 0xC0) == 0x80 and (b3 and 0xC0) == 0x80:
          (((b and 0x0F).int shl 12) or ((b2 and 0x3F).int shl 6) or (b3 and 0x3F).int, i + 3)
        else:
          (-1, i + 1)
      elif (b and 0xF8) == 0xF0 and i + 3 < input.len:
        let b2 = input[i + 1].uint8
        let b3 = input[i + 2].uint8
        let b4 = input[i + 3].uint8
        if (b2 and 0xC0) == 0x80 and (b3 and 0xC0) == 0x80 and (b4 and 0xC0) == 0x80:
          (((b and 0x07).int shl 18) or ((b2 and 0x3F).int shl 12) or
            ((b3 and 0x3F).int shl 6) or (b4 and 0x3F).int, i + 4)
        else:
          (-1, i + 1)
      else:
        (-1, i + 1) # Invalid UTF-8
    
    if cp == -1: # Invalid UTF-8
      output.add(input[i ..< nextI]) # Pass through invalid bytes as-is
      i = nextI
      continue

    # --- JavaScriptEncoder logic ---

    if cp < 128: # ASCII
      if (encoder.validMasks[cp shr 5] and (1'u32 shl (cp and 31))) != 0:
        output.add(char(cp)) #
      else:
        # Needs encoding
        case cp
        of '\b'.int: output.add("\\b")
        of '\t'.int: output.add("\\t")
        of '\n'.int: output.add("\\n")
        of '\f'.int: output.add("\\f")
        of '\r'.int: output.add("\\r")
        of '\''.int, '"'.int:
          if encoder.hexEncodeQuotes:
            output.add(fmt"\\x{cp:02x}")
          else:
            output.add('\\')
            output.add(char(cp))
        of '\\'.int, '/'.int, '-'.int, '&'.int:
          output.add('\\')
          output.add(char(cp))
        else: # Other C0 controls, \v, etc.
          output.add(fmt"\\x{cp:02x}")
    else: # Non-ASCII
      if encoder.asciiOnly or cp == LINE_SEPARATOR or cp == PARAGRAPH_SEPARATOR:
        if cp <= 0xFF:
          output.add(fmt"\\x{cp:02x}")
        else:
          output.add(fmt"\\u{cp:04x}")
      else:
        output.add(input[i ..< nextI]) # Pass through valid Unicode

    i = nextI