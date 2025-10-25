import benchy
import strutils      # For newString and string manipulation
import owasp_encoder # Your Nim OWASP Encoder library
import std/os        # For timeIt's underlying functionality (optional but good practice)
import std/streams


# --- 1. Configuration & Test Data Generation ---

const 
  # Size of the input string for a single encoding call (100 KB)
  MaxInputSize = 100_000 
  
# Function to create a large string containing characters likely to be encoded.
# This is crucial for a real-world performance test.
proc generateEvilString(size: int): string =
  result = newString(size)
  # Mixes standard characters with those that require encoding in various contexts: 
  # HTML (<>&"'), JavaScript (', /), and URI (&).
  let evilChars = "<>&\"'/ "
  for i in 0 ..< size:
    if i mod 10 == 0:
      # Inject an evil character every 10 characters
      result.add(evilChars[i mod evilChars.len])
    else:
      # Use a type cast to convert the ASCII integer value to a character
      result.add(char(65 + i mod 26)) 

# --- 2. Setup (Runs once) ---

# Generate the common input data once
let
  testInput = generateEvilString(MaxInputSize)
  
# --- 3. Benchmarks using timeIt ---

when isMainModule:
  echo "--- OWASP Nim Encoder Performance (100KB Input) ---"

  # Benchmark 1: HTML Content Encoding
  # Use timeIt to benchmark the forHtmlContent procedure
  timeIt "forHtmlContent":
    discard forHtmlContent(testInput)

  # Benchmark 2: HTML Attribute Encoding
  timeIt "forHtmlAttribute":
    discard forHtmlAttribute(testInput)
    
  # Benchmark 3: JavaScript Block Encoding
  timeIt "forJavaScriptBlock":
    discard forJavaScriptBlock(testInput)

  # Benchmark 4: URI Component Encoding
  timeIt "forUriComponent":
    discard forUriComponent(testInput)

  # Benchmark 5: CSS String Encoding
  timeIt "forCssString":
    discard forCssString(testInput)
