# owasp_encoder

[![License: BSD-3-Clause](https://img.shields.io/badge/License-BSD--3--Clause-blue.svg)](https://opensource.org/licenses/BSD-3-Clause)

A Nim port of the industry-standard [OWASP Java Encoder](https://github.com/OWASP/owasp-java-encoder) library.

This library provides context-aware, secure output encoding to help developers prevent Cross-Site Scripting (XSS) and other injection vulnerabilities.

It is a faithful port that passes the complete test suite from the original Java project, ensuring identical behavior and security. (The only component not ported is the `JavaEncoder`, which is not relevant for Nim).

## What is this and when do I use it?

**What it does:** This library stops Cross-Site Scripting (XSS) attacks. It takes untrusted data (like a username, comment, or URL parameter) and escapes it so it's safe to put inside your web page.

**When to use it:** Any time you are placing data from an external source (a user, a database, an API) into an HTML, CSS, or JavaScript context.
- Use `forHtmlContent(...)` before putting text in a `<div>` or `<span>`.

- Use `forHtmlAttribute(...)` before putting text in an `href` or `title` attribute.

- Use `forJavaScriptBlock(...)` before putting text inside a `<script>` block.

## Features

* **Context-Aware:** Provides different encoders for different output contexts (HTML, XML, CSS, JavaScript, URI). 
* **Secure by Default:** Implements the same robust encoding rules as the battle-tested Java original.
* **Simple API:** Offers a clear set of `for...` procedures that mirror the static methods in the Java `Encode` class. 
* **Flexible:** Provides procedures that return an encoded `string` or write directly to a `Stream`. 
* **Optimized:** Avoids new string allocations if the input string contains no characters that need encoding. 

## Installation

You can install the library via Nimble:

```bash
nimble install owasp_encoder
```

## Usage

Import the main `owasp_encoder` module to access all encoding procedures.

```nim
import owasp_encoder
import std/streams
```

### Basic String Encoding

The library provides a `for...` function for each context.

**HTML Example:**
Encodes for HTML body content.

```nim
let untrusted = "John's <strong>profile</strong>"

# Encodes for HTML attribute content
let safeAttr = forHtmlAttribute(untrusted)
echo "Setting attribute: <a title='" & safeAttr & "'>...</a>"
# Output: Setting attribute: <a title='John&#39;s &lt;strong>profile&lt;/strong>'>...</a>

# Encodes for HTML text content
let safeContent = forHtmlContent(untrusted)
echo "Setting content: <div>" & safeContent & "</div>"
# Output: Setting content: <div>John's &lt;strong&gt;profile&lt;/strong&gt;</div>
```

**JavaScript Example:**
Encodes for a string within a JavaScript block.

```nim
let username = "O'Malley</script>"
let jsString = forJavaScriptBlock(username)

echo "var username = '" & jsString & "';"
# Output: var username = 'O\'Malley<\/script>';
```

**URI Example:**
Encodes for a component of a URI (like a query parameter).

```nim
let query = "search&go=true"
let encodedQuery = forUriComponent(query)

echo "https://example.com/search?q=" & encodedQuery
# Output: https://example.com/search?q=search%26go%3Dtrue
```

**CSS Example:**
Encodes for a value within a CSS string.

```nim
let fontName = "'Arial'"
let safeCss = forCssString(fontName)

echo "font-family: " & safeCss & ";"
# Output: font-family: \27 Arial\27;
```

### Stream-Based Encoding

For performance and lower memory usage, you can encode directly to any `Stream` (from `std/streams`). This is ideal for writing to files or network sockets.

All `for...` procedures are overloaded to accept a `Stream` as the first argument.

```nim
import std/streams

let s = newStringStream()
let untrusted = "A \"dangerous\" <script>"

# Write encoded content directly to the stream
s.write("<div>")
forHtml(s, untrusted)
s.write("</div>")

echo s.data
# Output: <div>A &#34;dangerous&#34; &lt;script&gt;</div>
```

## Available Encoders

This library provides encoders for all major web contexts: 

### HTML / XML
* `forHtml(input)`: Encodes for (X)HTML text content and attributes. 
* `forHtmlContent(input)`: Encodes for HTML text content only. 
* `forHtmlAttribute(input)`: Encodes for HTML attribute values. 
* `forHtmlUnquotedAttribute(input)`: Encodes for unquoted HTML attribute values. 
* `forXml(input)`: Alias for `forHtml`. 
* `forXmlContent(input)`: Alias for `forHtmlContent`. 
* `forXmlAttribute(input)`: Alias for `forHtmlAttribute`. 
* `forXmlComment(input)`: Encodes for XML comments. 
* `forCDATA(input)`: Encodes for XML CDATA sections. 

### JavaScript
* `forJavaScript(input)`: Encodes for JS string in HTML attribute or block. 
* `forJavaScriptAttribute(input)`: Encodes for JS string in an HTML attribute (e.g., `onclick`). 
* `forJavaScriptBlock(input)`: Encodes for JS string in a `<script>` block. 
* `forJavaScriptSource(input)`: Encodes for a JS string in a `.js` or JSON file. 

### CSS
* `forCssString(input)`: Encodes for CSS strings. 
* `forCssUrl(input)`: Encodes for CSS `url()` contexts. 

### URI
* `forUriComponent(input)`: Encodes for a URI component (percent-encoding). 

*All procedures are also available as `proc(output: Stream, input: string)`.*

## License

This library is licensed under the **BSD 3-Clause "New" or "Revised" License**, the same license as the original [OWASP Java Encoder](https://github.com/OWASP/owasp-java-encoder/blob/main/LICENSE.txt).