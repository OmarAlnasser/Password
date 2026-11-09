"""Writes Strings.resx and Strings.ar.resx from the tables in tools/strings_*.py.

The .resx files are what the app ships and what translators edit; this script exists so the two
languages are always generated together and stay in key parity.
Run: python3 -I tools/gen_resx.py
"""
import glob, importlib.util, os, sys
from xml.sax.saxutils import escape

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "src", "PcDoctor.Core", "Resources")
HEADER = """<?xml version="1.0" encoding="utf-8"?>
<root>
  <resheader name="resmimetype"><value>text/microsoft-resx</value></resheader>
  <resheader name="version"><value>2.0</value></resheader>
  <resheader name="reader"><value>System.Resources.ResXResourceReader, System.Windows.Forms, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089</value></resheader>
  <resheader name="writer"><value>System.Resources.ResXResourceWriter, System.Windows.Forms, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089</value></resheader>
"""

rows, seen = [], set()
for path in sorted(glob.glob(os.path.join(HERE, "strings_*.py"))):
    spec = importlib.util.spec_from_file_location(os.path.basename(path)[:-3], path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    for key, en, ar in mod.S:
        if key in seen:
            sys.exit(f"duplicate key {key} in {path}")
        seen.add(key)
        rows.append((key, en, ar))

for name, col in (("Strings.resx", 1), ("Strings.ar.resx", 2)):
    with open(os.path.join(OUT, name), "w", encoding="utf-8", newline="\n") as f:
        f.write(HEADER)
        for row in rows:
            f.write(f'  <data name="{escape(row[0])}" xml:space="preserve"><value>{escape(row[col])}</value></data>\n')
        f.write("</root>\n")
print(f"{len(rows)} keys")
