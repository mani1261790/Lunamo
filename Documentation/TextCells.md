# Native text-cell command v1

The pinned upstream marimo-lsp server is extended by the bundled launcher with
`marimonative/textCell`. The upstream `marimo/command` schema is unchanged.
This extension has not been published upstream. Swift never parses or rewrites
`mo.md` strings.

Request: `{ "source": string, "markdown": string | null }`.
Response: `{ "source": string, "markdown": string | null }`.
A null input Markdown requests projection; a non-null value requests an edit.
Empty source plus Markdown creates a self-contained, binding-free
`__import__("marimo").md(...)` expression, so text cells do not repeat a private
import alias. Only a sole static string argument to `mo.md`, a direct marimo import
alias, or that exact binding-free form is projected. Python's AST validates the
structure; no notebook expression is evaluated. Unchanged text returns the original
source byte-for-byte. Editing replaces the literal using Python's string serializer,
retaining surrounding code. Dynamic f-strings, keyword arguments and mixed-code
cells remain ordinary Python.
This is a conservative first slice of Issue #26, not full upstream Smart Cells
interpolation/SQL parity.

The displayed Markdown is transient; save, export and execution continue to use
the owned Python source. Pending conversions participate in the save/run flush
barrier. Conversion failures block saving stale source until corrected. In its
resting state a text cell is rendered directly on the notebook canvas without a
code-cell card, run rail, or execution count. Double-clicking enters a temporary
bordered Markdown editor; leaving that editor automatically returns to the document
presentation. Cell actions and insertion controls use contextual hover disclosure.
The native block
renderer supports headings, paragraphs, inline emphasis and links, unordered and
ordered lists, quotes, fenced code, and horizontal rules. It does not execute
Python to preview static text.

Verification: `Tests/Contract/test_text_cells.py` checks static literal round trips,
quotes, raw strings, Unicode, indentation, braces, backslashes and dynamic-source
fallback. `textCellRoundTrip` checks the real LSP extension through notebook
print/parse. `MarkdownDocumentParserTests` covers the native block structure.
Full interpolation editing and advanced Markdown such as tables, task lists, and
embedded local media remain out of this slice.
