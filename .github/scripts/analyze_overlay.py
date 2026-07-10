#!/usr/bin/env python3
# .github/scripts/analyze_overlay.py
import os
import sys
import xml.etree.ElementTree as ET

def analyze_xml(filepath):
    """Periksa file XML resource untuk masalah umum."""
    errors = []
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
    except ET.ParseError as e:
        return [f"Parse error in {filepath}: {e}"]

    # 1. Cek string kosong
    for elem in root.findall(".//string"):
        name = elem.get("name")
        text = elem.text or ""
        if not text.strip():
            errors.append(f"Empty string: '{name}' in {filepath}")

    # 2. Cek string-array kosong
    for elem in root.findall(".//string-array"):
        name = elem.get("name")
        items = elem.findall("item")
        if not items:
            errors.append(f"Empty string-array: '{name}' in {filepath}")

    # 3. Cek duplikasi nama resource dalam satu file
    names = {}
    for elem in root.findall(".//*[@name]"):
        name = elem.get("name")
        if name in names:
            errors.append(f"Duplicate resource name '{name}' in {filepath}")
        else:
            names[name] = True

    # 4. (Opsional) Cek warna valid (format #AARRGGBB)
    for elem in root.findall(".//color"):
        color = elem.text or ""
        if color and not color.startswith("#"):
            errors.append(f"Invalid color format '{color}' in {filepath}")

    return errors

def main():
    # Ambil daftar direktori dari argumen; default ke ['res']
    dirs = sys.argv[1:] if len(sys.argv) > 1 else ['res']
    all_errors = []

    for base_dir in dirs:
        if not os.path.isdir(base_dir):
            print(f"⚠️  Directory '{base_dir}' not found. Skipping.")
            continue

        for root, _, files in os.walk(base_dir):
            for file in files:
                if file.endswith('.xml'):
                    filepath = os.path.join(root, file)
                    errors = analyze_xml(filepath)
                    all_errors.extend(errors)

    if all_errors:
        print("❌ Overlay analysis found issues:")
        for err in all_errors:
            print(f"  - {err}")
        sys.exit(1)
    else:
        print("✅ All overlay XML files passed validation.")

if __name__ == "__main__":
    main()
