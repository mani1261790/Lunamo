"""Pinned upstream server with a native, non-executing text-cell command."""
import ast
import logging

from marimo_lsp.kernels.native import NativeKernels
from marimo_lsp.saved_session_store import LocalSavedSessionFiles
from marimo_lsp.server import create_server, _json_rpc_value
from marimo_lsp.loggers import get_logger, lsp_handler


MAXIMUM_IMPORT_BYTES = 20 * 1024 * 1024
MAXIMUM_COMPLETION_BYTES = 1 * 1024 * 1024


def complete_python(params):
    """Return static Python completions without executing notebook code."""
    params = _json_rpc_value(params)
    source = params.get("source", "")
    line = params.get("line", 0)
    column = params.get("column", 0)
    if not isinstance(source, str) or len(source.encode("utf-8")) > MAXIMUM_COMPLETION_BYTES:
        return {"items": []}
    if not isinstance(line, int) or not isinstance(column, int) or line < 0 or column < 0:
        return {"items": []}

    import jedi

    try:
        completions = jedi.Script(code=source).complete(line=line + 1, column=column)
    except (ValueError, SyntaxError):
        return {"items": []}
    items = []
    seen = set()
    for completion in completions[:80]:
        if completion.name in seen:
            continue
        seen.add(completion.name)
        description = completion.description
        items.append({
            "label": completion.name,
            "detail": description if description != completion.name else None,
            "kind": completion.type,
        })
    return {"items": items}


def convert_notebook(params):
    """Convert external notebook text without evaluating user code."""
    params = _json_rpc_value(params)
    source = params.get("source", "")
    source_format = params.get("format")
    if not isinstance(source, str):
        raise ValueError("Import source must be text")
    if len(source.encode("utf-8")) > MAXIMUM_IMPORT_BYTES:
        raise ValueError("Import source is too large")

    from marimo._convert.converters import MarimoConvert

    if source_format == "ipynb":
        converted = MarimoConvert.from_ipynb(source).to_py()
    elif source_format == "python":
        converted = MarimoConvert.from_non_marimo_python_script(source).to_py()
    else:
        raise ValueError("Unsupported import format")
    return {"source": converted}


def text_cell(params):
    """Only static literals are editable. Never evaluate notebook expressions."""
    params = _json_rpc_value(params)
    source = params.get("source", "")
    markdown = params.get("markdown")
    if len(source) > 1_000_000 or (markdown is not None and len(markdown) > 1_000_000):
        raise ValueError("Text cell is too large")
    if not source:
        if markdown is None:
            return {"source": source, "markdown": None}
        # Keep text cells self-contained without defining the same import alias in
        # every cell. Python's module cache makes this a cheap, binding-free lookup.
        source = '__import__("marimo").md(' + repr(markdown) + ")"
        return {"source": source, "markdown": markdown}
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return {"source": source, "markdown": None}
    body = tree.body
    alias = "mo"
    if len(body) == 2 and isinstance(body[0], ast.Import):
        names = body[0].names
        if len(names) != 1 or names[0].name != "marimo":
            return {"source": source, "markdown": None}
        alias = names[0].asname or "marimo"
        body = body[1:]
    if len(body) != 1 or not isinstance(body[0], ast.Expr):
        return {"source": source, "markdown": None}
    call = body[0].value
    receiver = call.func.value if isinstance(call, ast.Call) and isinstance(
        call.func, ast.Attribute) else None
    direct_alias = isinstance(receiver, ast.Name) and receiver.id == alias
    binding_free_import = (
        isinstance(receiver, ast.Call)
        and isinstance(receiver.func, ast.Name)
        and receiver.func.id == "__import__"
        and len(receiver.args) == 1
        and not receiver.keywords
        and isinstance(receiver.args[0], ast.Constant)
        and receiver.args[0].value == "marimo"
    )
    if not (isinstance(call, ast.Call) and isinstance(call.func, ast.Attribute)
            and (direct_alias or binding_free_import)
            and call.func.attr == "md" and len(call.args) == 1 and not call.keywords
            and isinstance(call.args[0], ast.Constant) and isinstance(call.args[0].value, str)):
        return {"source": source, "markdown": None}
    literal = call.args[0]
    if markdown is None or markdown == literal.value:
        return {"source": source, "markdown": literal.value}
    # AST columns are UTF-8 byte offsets. Preserve all non-literal source, comments,
    # imports and surrounding whitespace; repr escapes quotes and backslashes safely.
    lines = source.encode("utf-8").splitlines(keepends=True)
    start = sum(map(len, lines[:literal.lineno - 1])) + literal.col_offset
    end = sum(map(len, lines[:literal.end_lineno - 1])) + literal.end_col_offset
    data = source.encode("utf-8")
    updated = (data[:start] + repr(markdown).encode("utf-8") + data[end:]).decode("utf-8")
    ast.parse(updated)
    return {"source": updated, "markdown": markdown}


def main():
    server = create_server(kernels=NativeKernels(), saved_session_files=LocalSavedSessionFiles())
    server.feature("marimonative/textCell")(text_cell)
    server.feature("marimonative/convertNotebook")(convert_notebook)
    server.feature("marimonative/completePython")(complete_python)
    logger = get_logger()
    logger.setLevel(logging.DEBUG)
    logger.addHandler(lsp_handler(server))
    server.start_io()


if __name__ == "__main__":
    main()
