# xmlencoder.nim
import encoder
import std/unicode # For Rune, runeAt, runeLenAt, and size

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
  let n = off + len
  var i = off
  while i < n:
    let charLen = runeLenAt(input, i)
    let cpRune = input.runeAt(i)
    let cp = cpRune.int
    let nextI = i + charLen

    # --- XMLEncoder-specific logic (from XMLEncoder.java) ---

    if charLen == 0:
      # Invalid UTF-8 sequence, flagged for replacement
      return i 

    elif cp < DEL: # 0-126 (Covers all non-encoded, non-valid ASCII)
      if (cp > '>'.int) or ((encoder.validMask and (1'u64 shl cp)) != 0):
        discard # Valid ASCII, continue
      else:
        # Needs encoding or is invalid ASCII control
        case cp:
        of '&'.int, '<'.int, '>'.int, '\''.int, '"'.int:
          return i # Needs encoding
        else:
          return i # Invalid control char e.g. \0, \1, etc.

    elif cp < MIN_HIGH_SURROGATE: # 127 (DEL) - 0xD7FF
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
          let charLen2 = runeLenAt(input, nextI)
          let cp2Rune = input.runeAt(nextI)
          let cp2 = cp2Rune.int
          let nextI2 = nextI + charLen2
          
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
              i = nextI2 # Consume both codepoints
              continue # Continue to next loop iteration
        
      # If we're here, it's an isolated surrogate (high or low)
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
  ## Encodes the input string using two loops: fast ASCII path + Rune processing.
  var i = 0
  var lastSafe = 0 
  
  while i < input.len:
    # --- FAST ASCII PASS-THROUGH LOOP (Bulk Skip) ---
    var fastI = i
    while fastI < input.len:
        let b = input[fastI].uint8
        
        # Break 1: Non-ASCII (b >= 127)
        if b >= DEL.uint8: break 

        # Break 2: Character requires encoding or special handling (Invalid control, encoded char).
        # This condition MUST be FALSE to continue skipping.
        # It replicates the Java logic: if (ch > '>' || ((_validMask & (1L << ch)) != 0))
        if not (b > '>'.uint8 or (encoder.validMask and (1'u64 shl b.int)) != 0):
            break
        
        fastI += 1

    # FLUSH: Copy the entire safe ASCII chunk if any was found
    if fastI > i:
        if i > lastSafe: output.add(input[lastSafe ..< i]) # Flush preceding Rune safe chunk
        output.add(input[i ..< fastI]) # Copy the new ASCII safe chunk
        lastSafe = fastI
        i = fastI
        continue # Restart outer loop (moves to Rune path only if no more ASCII skips are possible)

    # If we are here, 'i' points to a character that is non-ASCII or requires encoding/replacement.
    
    # --- RUNE PROCESSING LOOP (Single Character Handling) ---
    let charLen = runeLenAt(input, i)
    let cpRune = input.runeAt(i)
    let cp = cpRune.int
    let nextI = i + charLen

    if charLen == 0:
        # Invalid UTF-8 sequence
        if i > lastSafe: output.add(input[lastSafe ..< i])
        output.add(INVALID_CHARACTER_REPLACEMENT)
        i = i + 1 
        lastSafe = i
        continue

    elif cp < DEL: # 0-126
        # This path only handles encoded chars (like &) and control chars (like \n, \t) 
        # that were intentionally skipped by the fast path.
        if i > lastSafe: output.add(input[lastSafe ..< i])
        
        # EMIT: Encoded char or replacement
        case cp:
        of '&'.int: output.add("&amp;")
        of '<'.int: output.add("&lt;")
        of '>'.int: output.add("&gt;")
        of '\''.int: output.add("&#39;")
        of '"'.int: output.add("&#34;")
        else: output.add(INVALID_CHARACTER_REPLACEMENT) 
        
        lastSafe = nextI 

    elif cp < MIN_HIGH_SURROGATE: # 127 - 0xD7FF
      # Java logic: if (ch > Unicode.MAX_C1_CTRL_CHAR || ch == Unicode.NEL)
      if (cp > MAX_C1_CTRL_CHAR or cp == NEL):
        # Valid non-ASCII.
        discard 
      else:
        # FLUSH: Emit preceding safe chunk
        if i > lastSafe: output.add(input[lastSafe ..< i])
        
        # EMIT: Replacement
        output.add(INVALID_CHARACTER_REPLACEMENT)
        lastSafe = nextI 
        
    elif cp <= MAX_LOW_SURROGATE: # 0xD800 - 0xDFFF (Surrogate range)
      var handled = false
      if cp <= MAX_HIGH_SURROGATE:
        if nextI < input.len:
          let charLen2 = runeLenAt(input, nextI)
          let cp2Rune = input.runeAt(nextI)
          let cp2 = cp2Rune.int
          let nextI2 = nextI + charLen2
          
          if cp2 >= 0xDC00 and cp2 <= MAX_LOW_SURROGATE:
            let combinedCp = 0x10000 + ((cp - MIN_HIGH_SURROGATE) shl 10) + (cp2 - 0xDC00)

            if isNonCharacter(combinedCp):
              if i > lastSafe: output.add(input[lastSafe ..< i])
              output.add(INVALID_CHARACTER_REPLACEMENT)
              i = nextI2 
              lastSafe = i 
              handled = true
              continue 
            else:
              # Valid surrogate pair. Advance i.
              i = nextI2
              handled = true
              continue 
        
      if not handled:
        if i > lastSafe: output.add(input[lastSafe ..< i])
        output.add(INVALID_CHARACTER_REPLACEMENT)
        lastSafe = nextI 


    elif cp >= 0xFDD0: # Check for non-characters
      if isNonCharacter(cp):
        if i > lastSafe: output.add(input[lastSafe ..< i])
        output.add(INVALID_CHARACTER_REPLACEMENT) 
        lastSafe = nextI 
      elif cp <= 0x10FFFF:
        discard
      else:
        if i > lastSafe: output.add(input[lastSafe ..< i])
        output.add(INVALID_CHARACTER_REPLACEMENT) 
        lastSafe = nextI

    else:
      # All other valid chars (e.g., U+E000 - U+FDCF)
      discard

    # Advance i for non-encoded, non-surrogate characters.
    i = nextI
    
  # FINAL FLUSH: Copy the final safe chunk
  if input.len > lastSafe:
    output.add(input[lastSafe ..< input.len])