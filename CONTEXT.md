# MarimoNative

MarimoNative opens a marimo notebook as a native macOS document while delegating Python source interpretation and execution to the bundled marimo language server.

## Language

**Owned Notebook Document**:
The lossless, saveable notebook content received from and returned to marimo-lsp. It excludes every value that exists only while the document is open.
_Avoid_: Wire document, parsed model, notebook JSON

**Open Notebook**:
An Owned Notebook Document together with the stable identities and transient state needed while one native document is open.
_Avoid_: Session document, editor model

**Runtime Cell ID**:
A UUID v4 that identifies one cell for the lifetime of an Open Notebook, including edits, moves, and saves. It is never written to Python source.
_Avoid_: Cell ID, source ID, persistent ID

**Source Cell ID**:
An optional identifier read from marimo source and retained losslessly. It is not the identity used by the open editor.
_Avoid_: Runtime ID, stable ID

**Notebook Projection**:
The LSP notebook document and cell text documents derived from an Open Notebook. Projection metadata may include Runtime Cell IDs but does not change saveable content.
_Avoid_: Persistent model, source document

**Committed Edit**:
Text accepted by the input system and eligible to be synchronized to the language server. Marked text in an active input-method composition is not a Committed Edit.
_Avoid_: Keystroke, buffer update

**Dirty**:
The condition in which saveable notebook content differs from the last successful save. Runtime output, execution state, selection, and other transient changes never make a notebook Dirty.
_Avoid_: Changed, modified state

**Execution Environment**:
The selected Python installation and working directory in which an Open Notebook runs. It is distinct from the bundled service that reads and writes marimo source.
_Avoid_: Kernel, backend, sidecar

**Workspace**:
The local directory associated with an Open Notebook and shown in its Files browser. It supplies the trust and working context for execution without becoming part of the notebook itself.
_Avoid_: Project, repository, file tree

**Python Cell**:
A notebook cell whose saved content is Python source, including source that produces Markdown through marimo.
_Avoid_: Code block, Jupyter cell

**Smart Text Cell**:
A Markdown-focused editing projection that preserves the meaning of its corresponding Python Cell when opened and saved.
_Avoid_: Plain text cell, independent Markdown cell
