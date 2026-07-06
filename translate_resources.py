import os
import re
import json
import logging
import asyncio
import xml.etree.ElementTree as ET
from tqdm import tqdm
from deep_translator import GoogleTranslator
from googletrans import Translator as GoogletransAsync

# ================= KONFIGURASI =================
CACHE_FILE = "translation_cache.json"
LOG_FILE = "translate_pro.log"
SOURCE_LANG = "auto"
TARGET_LANG = "id"
OUTPUT_DIR = "values-in-rID"
# ===============================================

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE, encoding='utf-8'),
        logging.StreamHandler()
    ]
)

# Muat cache jika ada
cache = {}
if os.path.exists(CACHE_FILE):
    with open(CACHE_FILE, 'r', encoding='utf-8') as f:
        cache = json.load(f)
        logging.info(f"Cache dimuat: {len(cache)} entri")

def save_cache():
    with open(CACHE_FILE, 'w', encoding='utf-8') as f:
        json.dump(cache, f, ensure_ascii=False, indent=2)

def protect_placeholders(text):
    """Ganti placeholder dengan token unik agar tidak diterjemahkan."""
    pattern = r'%(\d*\$)?[sd]'
    tokens = {}
    def repl(match):
        token = f"__PH_{len(tokens)}__"
        tokens[token] = match.group(0)
        return token
    protected = re.sub(pattern, repl, text)
    return protected, tokens

def restore_placeholders(text, tokens):
    for token, placeholder in tokens.items():
        text = text.replace(token, placeholder)
    return text

def translate_text(text):
    """Terjemahkan teks dengan cache dan perlindungan placeholder."""
    if not text or not text.strip():
        return text

    key = text
    if key in cache:
        logging.debug(f"Dari cache: {text[:30]}...")
        return cache[key]

    protected, tokens = protect_placeholders(text)

    translated = None
    try:
        translated = GoogleTranslator(source=SOURCE_LANG, target=TARGET_LANG).translate(protected)
    except Exception as e1:
        logging.warning(f"deep-translator gagal: {e1}. Mencoba fallback...")
        try:
            async def fallback():
                async with GoogletransAsync() as translator:
                    result = await translator.translate(protected, src=SOURCE_LANG, dest=TARGET_LANG)
                    return result.text
            translated = asyncio.run(fallback())
        except Exception as e2:
            logging.error(f"Semua penerjemah gagal untuk: {text[:50]}... Error: {e2}")
            translated = protected

    if translated:
        translated = restore_placeholders(translated, tokens)
        cache[key] = translated
        save_cache()
        return translated
    else:
        return text

def translate_element(elem):
    if elem.text and elem.text.strip():
        elem.text = translate_text(elem.text)
    if elem.tail and elem.tail.strip():
        elem.tail = translate_text(elem.tail)
    for child in elem:
        translate_element(child)

def translate_xml_file(input_path):
    """Terjemahkan file XML dan simpan ke folder OUTPUT_DIR dengan nama yang sama."""
    # Buat folder tujuan jika belum ada
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    output_path = os.path.join(OUTPUT_DIR, os.path.basename(input_path))

    try:
        tree = ET.parse(input_path)
        root = tree.getroot()

        total_elements = sum(1 for _ in root.iter())
        with tqdm(total=total_elements, desc=f"Menerjemahkan {os.path.basename(input_path)}") as pbar:
            def translate_with_progress(elem):
                if elem.text and elem.text.strip():
                    elem.text = translate_text(elem.text)
                if elem.tail and elem.tail.strip():
                    elem.tail = translate_text(elem.tail)
                pbar.update(1)
                for child in elem:
                    translate_with_progress(child)
            translate_with_progress(root)

        tree.write(output_path, encoding='utf-8', xml_declaration=True)
        logging.info(f"Berhasil: {input_path} -> {output_path}")
    except Exception as e:
        logging.error(f"Gagal memproses {input_path}: {e}")

def main():
    files = ['arrays.xml', 'plurals.xml', 'strings.xml']
    for f in files:
        if os.path.exists(f):
            translate_xml_file(f)
        else:
            logging.warning(f"File {f} tidak ditemukan, dilewati.")

if __name__ == "__main__":
    main()
