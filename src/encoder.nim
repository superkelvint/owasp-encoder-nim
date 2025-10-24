## Encoder module providing base type and methods for string encoding.
import std/streams

type
  Encoder* = ref object of RootObj
    ## Base type for encoder implementations.

method encodeInternal*(encoder: Encoder, input: string, output: var string) {.base, raises: [].} =
  ## Default implementation that appends input to output without encoding.
  ## Subclasses should override this method to provide custom encoding.
  output.add(input)

method firstEncodedOffset*(encoder: Encoder, input: string, off: int, len: int): int {.base, raises: [].} =
  ## Finds the first character position that needs encoding.
  ## Default implementation indicates no encoding is needed.
  ## Returns the offset of the first character that needs encoding, or off + len if none.
  return off + len

proc encode*(encoder: Encoder, input: string): string =
  ## Encodes the input string.
  ##
  ## This proc includes an optimization from the original Java version:
  ## 1. It first calls `firstEncodedOffset` to find the first character that
  ##    needs encoding.
  ## 2. If no characters need encoding (`firstChange == input.len`), it returns
  ##    the original `input` string, avoiding any new string allocation.
  ## 3. If encoding is needed, it copies the safe prefix and then calls
  ##    `encodeInternal` to encode the rest of the string.

  # Handle nil input consistent with Java version
  if input == nil:
    return "null"

  let firstChange = encoder.firstEncodedOffset(input, 0, input.len)

  if firstChange == input.len:
    # Optimization: return input string if no changes
    return input

  # Estimate size.
  # Java's URIEncoder used 9.
  # We'll just grow dynamically, but start with a good guess.
  result = newString(input.len + (input.len - firstChange) * 8)
  result.setLen(0) # Make it empty

  # Add the part that was safe
  if firstChange > 0:
    result.add(input[0 ..< firstChange])

  # Encode the rest
  let rest = input[firstChange .. ^1]
  encoder.encodeInternal(rest, result)


proc encode*(encoder: Encoder, output: Stream, input: string) =
  ## Encodes the input string directly to a Stream (Nim's Writer).

  # Handle nil input consistent with Java version
  if input == nil:
    output.write("null")
    return

  let n = input.len
  let firstChange = encoder.firstEncodedOffset(input, 0, n)

  if firstChange == n:
    output.write(input) # Optimization: write string directly
    return

  # Write the safe prefix
  if firstChange > 0:
    output.write(input[0 ..< firstChange])

  # Encode the rest to a temporary string and write it.
  # This re-uses the existing `encodeInternal` logic.
  let rest = input[firstChange .. ^1]
  var encodedRest = ""
  encoder.encodeInternal(rest, encodedRest)
  output.write(encodedRest)