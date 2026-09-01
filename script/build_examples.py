#!/usr/bin/env python3
"""Convert the vendored Tatoeba Chinese-English MDX into a read-only SQLite DB."""

from __future__ import annotations

import argparse
import hashlib
import html
import re
import sqlite3
import sys
from pathlib import Path


FONT_RE = re.compile(r"<font\b[^>]*>(.*?)</font>", re.IGNORECASE | re.DOTALL)
LI_RE = re.compile(r"<li\b[^>]*>(.*?)</li>", re.IGNORECASE | re.DOTALL)
TAG_RE = re.compile(r"<[^>]+>")
HAN_RE = re.compile(r"[\u3400-\u9fff]")


def clean_markup(value: str) -> str:
    value = TAG_RE.sub(" ", value)
    value = html.unescape(value)
    return " ".join(value.replace("\u200b", "").split()).strip()


def normalized_pinyin(value: str) -> str:
    value = value.lower().replace("u:", "v").replace("ü", "v")
    return "".join(character for character in value if "a" <= character <= "z")


def parse_tsv(path: Path, columns: int) -> list[list[str]]:
    lines = path.read_text(encoding="utf-8").splitlines()
    parsed: list[list[str]] = []
    for line_number, line in enumerate(lines[1:], start=2):
        values = line.split("\t")
        if len(values) != columns:
            raise ValueError(f"Invalid TSV row at {path}:{line_number}")
        parsed.append(values)
    return parsed


def extract_record(record: bytes) -> tuple[str, list[str]] | None:
    markup = record.decode("utf-8", errors="replace")
    chinese_match = FONT_RE.search(markup)
    if not chinese_match:
        return None
    chinese = clean_markup(chinese_match.group(1))
    if not HAN_RE.search(chinese) or not (2 <= len(chinese) <= 160):
        return None
    english: list[str] = []
    for raw_item in LI_RE.findall(markup):
        if "Transl. Note:" in raw_item:
            continue
        sentence = clean_markup(raw_item)
        if 2 <= len(sentence) <= 320 and sentence not in english:
            english.append(sentence)
    return (chinese, english) if english else None


def quality_score(chinese: str, english: str, curated: bool) -> int:
    if curated:
        return 10_000
    score = 1_000 - abs(len(chinese) * 2 - len(english))
    if chinese[-1:] in "。！？?!" and english[-1:] in ".!?":
        score += 40
    return score


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source_directory", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    root = Path(__file__).resolve().parent.parent
    wheel = root / "script/vendor/mdict_utils-1.3.14-py3-none-any.whl"
    mdx_path = args.source_directory / "External/tatoeba_zh_en.mdx"
    if not wheel.exists() or not mdx_path.exists():
        raise FileNotFoundError("The vendored MDX reader and tatoeba_zh_en.mdx are required")
    sys.path.insert(0, str(wheel))
    from mdict_utils.base.readmdict import MDX  # type: ignore

    phrases = parse_tsv(args.source_directory / "phrases.tsv", 5)
    curated_examples = parse_tsv(args.source_directory / "phrase_examples.tsv", 4)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_name(f".{args.output.name}.{Path(__file__).stat().st_ino}.tmp")
    temporary.unlink(missing_ok=True)

    connection = sqlite3.connect(temporary)
    connection.executescript(
        """
        PRAGMA journal_mode=OFF;
        PRAGMA synchronous=OFF;
        PRAGMA user_version=1;
        CREATE TABLE phrases (
            stable_id TEXT PRIMARY KEY,
            pinyin TEXT NOT NULL,
            normalized_pinyin TEXT NOT NULL,
            chinese TEXT NOT NULL,
            english TEXT NOT NULL,
            priority INTEGER NOT NULL,
            source TEXT NOT NULL
        );
        CREATE INDEX phrases_longest_match
            ON phrases(normalized_pinyin, priority DESC, length(chinese) DESC);
        CREATE TABLE examples (
            example_id INTEGER PRIMARY KEY,
            chinese TEXT NOT NULL,
            english TEXT NOT NULL,
            source TEXT NOT NULL,
            quality_score INTEGER NOT NULL,
            UNIQUE(chinese, english)
        );
        CREATE TABLE example_terms (
            example_id INTEGER NOT NULL REFERENCES examples(example_id),
            term TEXT NOT NULL,
            PRIMARY KEY(example_id, term)
        );
        CREATE INDEX example_terms_lookup ON example_terms(term, example_id);
        CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        """
    )
    connection.execute("BEGIN IMMEDIATE")
    for stable_id, pinyin, chinese, english_text, priority in phrases:
        connection.execute(
            "INSERT INTO phrases VALUES (?, ?, ?, ?, ?, ?, 'linguaflow-reviewed')",
            (stable_id, pinyin, normalized_pinyin(pinyin), chinese, english_text, int(priority)),
        )

    example_ids: dict[tuple[str, str], int] = {}

    def add_example(term: str, chinese: str, english_text: str, source: str, curated: bool) -> None:
        pair = (chinese, english_text)
        example_id = example_ids.get(pair)
        if example_id is None:
            cursor = connection.execute(
                "INSERT OR IGNORE INTO examples(chinese,english,source,quality_score) VALUES (?,?,?,?)",
                (chinese, english_text, source, quality_score(chinese, english_text, curated)),
            )
            example_id = cursor.lastrowid
            if not example_id:
                example_id = connection.execute(
                    "SELECT example_id FROM examples WHERE chinese=? AND english=?", pair
                ).fetchone()[0]
            example_ids[pair] = example_id
        connection.execute(
            "INSERT OR IGNORE INTO example_terms(example_id,term) VALUES (?,?)",
            (example_id, term),
        )

    phrase_by_id = {row[0]: row for row in phrases}
    for phrase_id, chinese, english_text, source in curated_examples:
        phrase = phrase_by_id.get(phrase_id)
        if phrase is None:
            raise ValueError(f"Unknown phrase ID: {phrase_id}")
        add_example(phrase[2], chinese, english_text, source, True)

    mdx = MDX(str(mdx_path))
    imported_records = 0
    for raw_key, raw_record in mdx.items():
        term = raw_key.decode("utf-8", errors="replace").strip()
        if not HAN_RE.search(term) or len(term) > 24:
            continue
        parsed = extract_record(raw_record)
        if parsed is None:
            continue
        chinese, english_sentences = parsed
        for english_text in english_sentences:
            add_example(term, chinese, english_text, "tatoeba-mdx", False)
            imported_records += 1

    mdx_hash = hashlib.sha256(mdx_path.read_bytes()).hexdigest()
    metadata = {
        "schema_version": "1",
        "source": "Tatoeba Chinese-English Vocabulary MDX",
        "source_snapshot": "2020-12",
        "source_license": "CC BY 2.0 FR",
        "source_sha256": mdx_hash,
        "mdx_entries": str(len(mdx)),
        "imported_records": str(imported_records),
        "privacy": "No user input is stored",
    }
    connection.executemany("INSERT INTO metadata VALUES (?,?)", metadata.items())
    connection.commit()
    connection.execute("PRAGMA optimize")
    connection.close()
    args.output.unlink(missing_ok=True)
    temporary.replace(args.output)

    with sqlite3.connect(args.output) as verification:
        phrase_count = verification.execute("SELECT count(*) FROM phrases").fetchone()[0]
        example_count = verification.execute("SELECT count(*) FROM examples").fetchone()[0]
        link_count = verification.execute("SELECT count(*) FROM example_terms").fetchone()[0]
    print(f"Built {args.output} with {phrase_count} phrases, {example_count} examples, and {link_count} term links.")


if __name__ == "__main__":
    main()
