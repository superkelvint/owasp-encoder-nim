# owasp_encoder.nim
## Public API for the OWASP Encoder library.
## This module corresponds to the public static methods in `Encode.java`.

import encoder
import uriencoder
import cssencoder
import xmlencoder
import htmlencoder
import xmlcommentencoder
import cdataencoder
import javascriptencoder
import std/streams

# --- Global singleton encoders (like Encoders.java) ---

let
  XML_ENCODER* = newXMLEncoder(XMLEncoderMode.ALL)
  XML_CONTENT_ENCODER* = newXMLEncoder(XMLEncoderMode.CONTENT)
  XML_ATTRIBUTE_ENCODER* = newXMLEncoder(XMLEncoderMode.ATTRIBUTE)
  XML_COMMENT_ENCODER* = newXMLCommentEncoder()
  HTML_UNQUOTED_ATTRIBUTE_ENCODER* = newHTMLEncoder()
  CSS_STRING_ENCODER* = newCSSEncoder(CSSEncoderMode.STRING)
  CSS_URL_ENCODER* = newCSSEncoder(CSSEncoderMode.URL)
  URI_COMPONENT_ENCODER* = newURIEncoder(URIEncoderMode.COMPONENT)
  CDATA_ENCODER* = newCDATAEncoder()
  JAVASCRIPT_ENCODER* = newJavaScriptEncoder(JavaScriptEncoderMode.HTML, false)
  JAVASCRIPT_ATTRIBUTE_ENCODER* = newJavaScriptEncoder(JavaScriptEncoderMode.ATTRIBUTE, false)
  JAVASCRIPT_BLOCK_ENCODER* = newJavaScriptEncoder(JavaScriptEncoderMode.BLOCK, false)
  JAVASCRIPT_SOURCE_ENCODER* = newJavaScriptEncoder(JavaScriptEncoderMode.SOURCE, false)

# --- HTML / XML ---

proc forHtml*(input: string): string =
  ## Encodes for (X)HTML text content and text attributes.
  ## See Java documentation for details.
  result = encode(XML_ENCODER, input) #

proc forHtml*(output: Stream, input: string) =
  ## Writer version of forHtml
  encode(XML_ENCODER, output, input) #

proc forHtmlContent*(input: string): string =
  ## Encodes for HTML text content.
  ## See Java documentation for details.
  result = encode(XML_CONTENT_ENCODER, input) #

proc forHtmlContent*(output: Stream, input: string) =
  ## Writer version of forHtmlContent
  encode(XML_CONTENT_ENCODER, output, input) #

proc forHtmlAttribute*(input: string): string =
  ## Encodes for HTML text attributes.
  ## See Java documentation for details.
  result = encode(XML_ATTRIBUTE_ENCODER, input) #

proc forHtmlAttribute*(output: Stream, input: string) =
  ## Writer version of forHtmlAttribute
  encode(XML_ATTRIBUTE_ENCODER, output, input) #

proc forHtmlUnquotedAttribute*(input: string): string =
  ## Encodes for unquoted HTML attribute values.
  ## See Java documentation for details.
  result = encode(HTML_UNQUOTED_ATTRIBUTE_ENCODER, input) #

proc forHtmlUnquotedAttribute*(output: Stream, input: string) =
  ## Writer version of forHtmlUnquotedAttribute
  encode(HTML_UNQUOTED_ATTRIBUTE_ENCODER, output, input) #

proc forXml*(input: string): string =
  ## Encoder for XML and XHTML.
  result = encode(XML_ENCODER, input) #

proc forXml*(output: Stream, input: string) =
  ## Writer version of forXml
  encode(XML_ENCODER, output, input) #

proc forXmlContent*(input: string): string =
  ## Encoder for XML and XHTML text content.
  result = encode(XML_CONTENT_ENCODER, input) #

proc forXmlContent*(output: Stream, input: string) =
  ## Writer version of forXmlContent
  encode(XML_CONTENT_ENCODER, output, input) #

proc forXmlAttribute*(input: string): string =
  ## Encoder for XML and XHTML attribute content.
  result = encode(XML_ATTRIBUTE_ENCODER, input) #

proc forXmlAttribute*(output: Stream, input: string) =
  ## Writer version of forXmlAttribute
  encode(XML_ATTRIBUTE_ENCODER, output, input) #

proc forXmlComment*(input: string): string =
  ## Encoder for XML comments.
  result = encode(XML_COMMENT_ENCODER, input) #

proc forXmlComment*(output: Stream, input: string) =
  ## Writer version of forXmlComment
  encode(XML_COMMENT_ENCODER, output, input) #

proc forCDATA*(input: string): string =
  ## Encodes data for an XML CDATA section.
  result = encode(CDATA_ENCODER, input) #

proc forCDATA*(output: Stream, input: string) =
  ## Writer version of forCDATA
  encode(CDATA_ENCODER, output, input) #

# --- CSS ---

proc forCssString*(input: string): string =
  ## Encodes for CSS strings.
  result = encode(CSS_STRING_ENCODER, input) #

proc forCssString*(output: Stream, input: string) =
  ## Writer version of forCssString
  encode(CSS_STRING_ENCODER, output, input) #

proc forCssUrl*(input: string): string =
  ## Encodes for CSS URL contexts.
  result = encode(CSS_URL_ENCODER, input) #

proc forCssUrl*(output: Stream, input: string) =
  ## Writer version of forCssUrl
  encode(CSS_URL_ENCODER, output, input) #

# --- URI ---

proc forUriComponent*(input: string): string =
  ## Performs percent-encoding for a component of a URI.
  result = encode(URI_COMPONENT_ENCODER, input) #

proc forUriComponent*(output: Stream, input: string) =
  ## Writer version of forUriComponent
  encode(URI_COMPONENT_ENCODER, output, input) #

# --- JavaScript ---

proc forJavaScript*(input: string): string =
  ## Encodes for JavaScript string in either HTML attribute or block.
  ## See Java documentation for details.
  result = encode(JAVASCRIPT_ENCODER, input) #

proc forJavaScript*(output: Stream, input: string) =
  ## Writer version of forJavaScript
  encode(JAVASCRIPT_ENCODER, output, input) #

proc forJavaScriptAttribute*(input: string): string =
  ## Encodes for JavaScript string in an HTML attribute (e.g. onclick).
  ## See Java documentation for details.
  result = encode(JAVASCRIPT_ATTRIBUTE_ENCODER, input) #

proc forJavaScriptAttribute*(output: Stream, input: string) =
  ## Writer version of forJavaScriptAttribute
  encode(JAVASCRIPT_ATTRIBUTE_ENCODER, output, input) #

proc forJavaScriptBlock*(input: string): string =
  ## Encodes for JavaScript string in a <script> block.
  ## See Java documentation for details.
  result = encode(JAVASCRIPT_BLOCK_ENCODER, input) #

proc forJavaScriptBlock*(output: Stream, input: string) =
  ## Writer version of forJavaScriptBlock
  encode(JAVASCRIPT_BLOCK_ENCODER, output, input) #

proc forJavaScriptSource*(input: string): string =
  ## Encodes for a JavaScript string in a .js or JSON file.
  ## See Java documentation for details.
  result = encode(JAVASCRIPT_SOURCE_ENCODER, input) #

proc forJavaScriptSource*(output: Stream, input: string) =
  ## Writer version of forJavaScriptSource
  encode(JAVASCRIPT_SOURCE_ENCODER, output, input) #  