"""Export the flat Moon & Marimo mark for the landing page from the app artwork."""
from pathlib import Path
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent
ET.register_namespace("", "http://www.w3.org/2000/svg")
mark = ET.Element("{http://www.w3.org/2000/svg}svg", {"viewBox": "201 193 620 620"})
for layer in ("Moon", "Marimo"):
    mark.extend(ET.parse(root / "Lunamo.icon" / "Assets" / f"{layer}.svg").getroot())
ET.indent(mark)
(root.parents[1] / "site/assets/lunamo-mark.svg").write_bytes(ET.tostring(mark) + b"\n")
