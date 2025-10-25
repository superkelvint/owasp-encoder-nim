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
  ## Encodes the input string by iterating over Runes (Unicode codepoints)
  var i = 0
  var lastSafe = 0 # TRACKER: New variable to mark the start of the current safe chunk
  
  while i < input.len:
    let charLen = runeLenAt(input, i)
    let cpRune = input.runeAt(i)
    let cp = cpRune.int
    let nextI = i + charLen

    # --- XMLEncoder-specific logic (from XMLEncoder.java) ---

    if charLen == 0:
        # FLUSH: Emit preceding safe chunk
        if i > lastSafe: output.add(input[lastSafe ..< i])
        
        # EMIT: Replacement
        output.add(INVALID_CHARACTER_REPLACEMENT)
        
        i = i + 1 # Must advance by at least one byte on error
        lastSafe = i # UPDATE: Mark the start of the new safe chunk
        continue

    elif cp < DEL: # 0-126
      if (cp > '>'.int) or ((encoder.validMask and (1'u64 shl cp)) != 0):
        # Valid ASCII, DO NOT FLUSH/EMIT, just continue to extend the safe chunk
        discard 
      else:
        # FLUSH: Emit preceding safe chunk
        if i > lastSafe: output.add(input[lastSafe ..< i])
        
        # EMIT: Encoded char or replacement
        case cp:
        of '&'.int: output.add("&amp;")
        of '<'.int: output.add("&lt;")
        of '>'.int: output.add("&gt;")
        of '\''.int: output.add("&#39;")
        of '"'.int: output.add("&#34;")
        else: output.add(INVALID_CHARACTER_REPLACEMENT) # e.g. \0, \1, etc.
        
        lastSafe = nextI # UPDATE: Mark the start of the new safe chunk

    elif cp < MIN_HIGH_SURROGATE: # 127 - 0xD7FF
      # Java logic: if (ch > Unicode.MAX_C1_CTRL_CHAR || ch == Unicode.NEL)
      if (cp > MAX_C1_CTRL_CHAR or cp == NEL):
        # Valid non-ASCII, continue to extend the safe chunk
        discard
      else:
        # FLUSH: Emit preceding safe chunk
        if i > lastSafe: output.add(input[lastSafe ..< i])
        
        # EMIT: Replacement
        output.add(INVALID_CHARACTER_REPLACEMENT)
        
        lastSafe = nextI # UPDATE: Mark the start of the new safe chunk
        
    elif cp <= MAX_LOW_SURROGATE: # 0xD800 - 0xDFFF (Surrogate range)
      var handled = false
      # Check if it's a HIGH surrogate (0xD800 - 0xDBFF)
      if cp <= MAX_HIGH_SURROGATE:
        # It's a high surrogate. Peek at the next codepoint.
        if nextI < input.len:
          let charLen2 = runeLenAt(input, nextI)
          let cp2Rune = input.runeAt(nextI)
          let cp2 = cp2Rune.int
          let nextI2 = nextI + charLen2
          
          # Check if next is a LOW surrogate (0xDC00 - 0xDFFF)
          if cp2 >= 0xDC00 and cp2 <= MAX_LOW_SURROGATE:
            # We have a valid pair!
            let combinedCp = 0x10000 + ((cp - MIN_HIGH_SURROGATE) shl 10) + (cp2 - 0xDC00)

            if isNonCharacter(combinedCp):
              # FLUSH: Emit preceding safe chunk
              if i > lastSafe: output.add(input[lastSafe ..< i])
              # EMIT: Invalid pair is replaced by *one* space.
              output.add(INVALID_CHARACTER_REPLACEMENT)
              
              i = nextI2 # Consume both codepoints
              lastSafe = i # UPDATE: Mark the start of the new safe chunk
              handled = true
              continue # Continue to next loop iteration
            else:
              # Valid surrogate pair. Continue to extend the safe chunk.
              i = nextI2
              handled = true
              continue # Continue to next loop iteration
        
      if not handled:
        # FLUSH: Emit preceding safe chunk
        if i > lastSafe: output.add(input[lastSafe ..< i])
        
        # This handles isolated surrogates (high or low)
        output.add(INVALID_CHARACTER_REPLACEMENT)
        lastSafe = nextI # UPDATE: Mark the start of the new safe chunk


    elif cp >= 0xFDD0: # Check for non-characters
      if isNonCharacter(cp):
        # FLUSH: Emit preceding safe chunk
        if i > lastSafe: output.add(input[lastSafe ..< i])
        # EMIT: Replacement
        output.add(INVALID_CHARACTER_REPLACEMENT) 
        lastSafe = nextI # UPDATE: Mark the start of the new safe chunk
      elif cp <= 0x10FFFF:
        # Valid, continue to extend the safe chunk
        discard
      else:
        # FLUSH: Emit preceding safe chunk
        if i > lastSafe: output.add(input[lastSafe ..< i])
        # EMIT: Replacement (> 0x10FFFF)
        output.add(INVALID_CHARACTER_REPLACEMENT) 
        lastSafe = nextI # UPDATE: Mark the start of the new safe chunk

    else:
      # All other valid chars (e.g., U+E000 - U+FDCF)
      # Valid, continue to extend the safe chunk
      discard

    i = nextI
    
  # FINAL FLUSH: Copy the final safe chunk
  if input.len > lastSafe:
    output.add(input[lastSafe ..< input.len])