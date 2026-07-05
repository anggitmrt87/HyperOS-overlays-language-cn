# Android Resource Files Translator (arrays.xml, plurals.xml, strings.xml)

A Python script to automatically translate Android resource files (`arrays.xml`, `plurals.xml`, `strings.xml`) from any source language (auto-detected) to Indonesian. It features caching, progress bars, placeholder protection, and API fallback for reliable and fast performance.

---

## 🚀 Key Features

- **Auto-detect source language** – no need to manually specify the input language.
- **Translation cache** – stores results in `translation_cache.json` to speed up subsequent runs.
- **Placeholder protection** – preserves Android placeholders like `%s`, `%d`, `%1$s`, `%2$s`, etc.
- **Progress bar** – visual tracking of translation progress per file using `tqdm`.
- **Fallback API** – if `deep-translator` fails, it falls back to `googletrans` automatically.
- **Detailed logging** – all activities and errors are logged to `translate_pro.log`.
- **No backup** – keeps your directory clean by not creating backup copies of original files.
- **Separate output** – translated files are saved with the `_id.xml` suffix (e.g., `strings_id.xml`).

---

## 📦 Prerequisites

Ensure you have Python 3.7 or higher installed.

Install the required libraries:

```bash
pip install deep-translator googletrans==4.0.0-rc1 tqdm