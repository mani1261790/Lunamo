# Lunamo

## Product naming

The product name is **Lunamo** (ルナモ). Use `lunamo` for the executable and command-line examples. The planned remote execution companion is **Lunamo Host**; it is not implemented yet. The visual motif is a small green planet inspired by the moon and marimo.

Builds produce `Lunamo.app`, with the `lunamo` executable. Open `Lunamo.xcodeproj` and select the `Lunamo` scheme. Existing source module names and the `MarimoNative/` source directory are implementation details. Keep the `dev.marimonative.app` bundle identifier, Application Support paths, trust records, and `marimonative/*` protocol identifiers stable so the rename preserves existing settings, notebooks, environments, and sidecar compatibility. The specification retains its existing filename.

## Assistant interaction

The native trailing sidebar is dedicated to Assistant; it is not a switchable status Inspector. It is attached inside the notebook detail hierarchy before the window toolbar modifier, so the toolbar spans the window and the Assistant begins below it instead of consuming toolbar layout. Python environments, packages, and execution safety belong in the app Settings window. Variables remain bounded runtime state and are not promoted into a persistent settings or status panel. The Assistant is a conversation, not a modal preview. Its header offers New Conversation and History; it does not duplicate the toolbar Assistant toggle with a second close button. Starting a new conversation archives a non-empty conversation in a bounded, in-memory history for the current notebook session, and selecting an entry restores it. This history is deliberately not written to disk and is cleared with the conversation when document identity changes, preventing code or attachments from crossing notebook boundaries. A paperclip opens the system file importer for images and files, while a separate code-context control explicitly attaches one or more cell snapshots. Changing selection or editing a cell does not silently alter previously sent context. When a response contains exactly one complete Python replacement for one attached code cell, the Assistant may stage it as a Generated Preview. The preview shows the original and proposed source and applies only after explicit confirmation through the normal Committed Edit path. If the cell changed or disappeared after generation, application is refused. Smart Text Cells, multi-cell edits, filesystem changes, terminal commands, saving, and execution remain outside this authority. Conversation state survives sidebar closing and reopening but resets when the open document identity changes. Generation uses the on-device model and never saves or executes notebook code. Text files are provided as reference source; image understanding uses the system model's native image attachment support where available. Long conversations must start a new conversation rather than silently dropping context.

Lunamo opens a marimo notebook as a native macOS document while delegating Python source interpretation and execution to the bundled marimo language server.

## Notebook chrome

The toolbar keeps document, shell, execution, and Assistant actions semantically separate. A single document title remains in the leading navigation position and directly opens the native Save As flow so the user can name the notebook and choose its location; no centered or duplicate title control is added. After a successful save, that folder becomes the Workspace shown in Files. Python environment selection belongs in Settings rather than the toolbar. The terminal symbol opens a resizable bottom terminal inside the notebook detail column, so it never covers Files or the trailing Assistant. Prompt, command editing, and output share one continuous scrollback surface; there is no separate command field or input footer. The terminal accepts only commands explicitly entered by the user. When the Open Notebook has a private Notebook Environment, the Notebook Terminal uses that same Python and package set.
Untitled notebooks start in the app-managed `Application Support/MarimoNative/Notebooks` Workspace, so selecting a working directory is not a first-run requirement. This folder avoids macOS Documents-folder privacy prompts, is created locally without requiring an iCloud entitlement, and is trusted as app-managed storage. Settings shows the resolved folder and keeps manual working-directory selection under Advanced for notebooks that need another location. After Save As, the saved notebook's parent directory becomes its Workspace and retains the normal folder-trust boundary. The Notebook Terminal starts in the current Workspace, including the app folder before the first save.

## Coding assistance

Python completion is a non-executing editor service. The native TextKit editor requests static completions from bundled Jedi through the pinned sidecar command and presents them with the macOS completion UI; automatic requests are debounced, bounded, and may also be requested with Control-Space. Command-I opens a cell-local Assistant composer. If source is selected, only that selected source is sent as code context; an eligible generated replacement is merged back into the unchanged cell locally and still requires Generated Preview confirmation. Cell context menus expose Explain Code, Fix or Improve Code, and Generate Tests using the same explicit attachment and review boundary. Runtime errors expose Explain Error and Suggest Fix, but neither action executes or applies code automatically.

## Notebook import

Lunamo treats marimo `.py` as the only editable canonical document format. Opening `.ipynb` or a non-marimo Python script invokes the converter from the pinned bundled marimo sidecar without running notebook code. The converted result must parse as a marimo notebook before it can be saved. Jupyter package-install cells become declared requirements: import never runs them or silently changes an environment. Lunamo presents those requirements for explicit installation into the Notebook Environment after conversion. Import always uses a native Save panel and writes to a separate `.py` URL; cancelling leaves the source and current document unchanged. A regular Python script defaults to `<name>_marimo.py`, while a Jupyter notebook defaults to `<name>.py`.

## Execution environment clarity

The settings UI presents one Notebook Environment as the place used by execution, package installation, and the Notebook Terminal. Opening Settings may run the fixed, non-user-code Python preflight against discovered candidates so availability is known before selection. The pinned Python shipped inside the app is a zero-setup bootstrap and execution fallback, but is never modified. Package installation defaults to one versioned Shared Environment below Lunamo's Application Support directory. A project opts into a separate app-managed Project Environment only when it needs incompatible package versions; Lunamo does not create a `.venv` beside every notebook. The selected strategy is remembered per workspace. Package Inventory always names the exact environment it reads. Settings shows app-managed environment size, last use, and current status, and offers confirmation-gated rebuild, Trash, 30-day unused-project cleanup, and app-private uv cache cleanup. Cleanup touches only paths created below Lunamo's managed environment/cache roots.

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

**Notebook Environment**:
The private, writable Python environment shared by notebook execution, package installation, and the Notebook Terminal. Lunamo may prepare it from a compatible Execution Environment, but never treats the application bundle or macOS Python as writable package storage.
_Avoid_: Global Python, built-in Python, package folder

**Workspace**:
The local directory associated with an Open Notebook and shown in its Files browser. It supplies the trust and working context for execution without becoming part of the notebook itself.
_Avoid_: Project, repository, file tree

**Notebook Terminal**:
The user-controlled shell terminal shown below the Notebook canvas. Its prompt, editable current command, history, and output form one continuous scrollback surface. It starts in the saved Workspace and uses the Notebook Environment when one exists.
_Avoid_: Python environment selector, kernel console, split command field

**Python Cell**:
A notebook cell whose saved content is Python source, including source that produces Markdown through marimo.
_Avoid_: Code block, Jupyter cell

**Smart Text Cell**:
A Markdown-focused editing projection that preserves the meaning of its corresponding Python Cell when opened and saved.
_Avoid_: Plain text cell, independent Markdown cell

**Package Inventory**:
The list of packages resolved from the exact Python executable in the current Notebook Environment. Reading it does not itself authorize a package change.
_Avoid_: Terminal, package installer, global environment

**Notebook Assistant**:
A user-initiated, on-device Apple Intelligence action over the selected cell. It has no background access to notebook content and never saves or executes generated source.
_Avoid_: Siri integration, AI chat, cloud assistant

**Generated Preview**:
Assistant output held outside the Owned Notebook Document until the user explicitly applies it to the selected cell. Applying it creates a normal Committed Edit only.
_Avoid_: Auto-fix, generated cell, executed suggestion
