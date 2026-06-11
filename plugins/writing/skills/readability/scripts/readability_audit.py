#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Readability audit for prose/markdown.

Usage: readability_audit.py <file> [--branch BRANCH] [--target-grade N]
"""

import argparse
import math
import re
import subprocess
import sys
from collections import namedtuple
from pathlib import Path

LONG_SENTENCE_WORDS = 25
LONG_PARAGRAPH_WORDS = 120

CheckResult = namedtuple("CheckResult", ["status", "label", "details"])


class ReadabilityAudit:
    def __init__(self, text):
        self._original_text = text
        self._normalized_text = self._normalize_text(text)
        self._metrics = None

    def metrics(self):
        if self._metrics is not None:
            return self._metrics

        words = self._extract_words(self._normalized_text)
        sentences = self._extract_sentences(self._normalized_text)
        paragraphs = self._extract_paragraphs(self._normalized_text)

        sentence_lengths = [len(self._extract_words(s)) for s in sentences]
        paragraph_lengths = [len(self._extract_words(p)) for p in paragraphs]

        self._metrics = {
            "words": len(words),
            "sentences": max(len(sentences), 1),
            "paragraphs": max(len(paragraphs), 1),
            "heading_count": self._heading_count(self._original_text),
            "list_item_count": self._list_item_count(self._original_text),
            "avg_words_per_sentence": self._average(sentence_lengths),
            "avg_words_per_paragraph": self._average(paragraph_lengths),
            "long_sentence_ratio": self._ratio(
                sum(1 for c in sentence_lengths if c > LONG_SENTENCE_WORDS),
                len(sentence_lengths),
            ),
            "long_paragraph_ratio": self._ratio(
                sum(1 for c in paragraph_lengths if c > LONG_PARAGRAPH_WORDS),
                len(paragraph_lengths),
            ),
            "first_paragraph_words": paragraph_lengths[0] if paragraph_lengths else 0,
            "flesch_kincaid_grade": self._flesch_kincaid_grade(words, sentences),
        }
        return self._metrics

    def checks(self, target_grade=10):
        m = self.metrics()
        results = []

        results.append(
            self._threshold_check(
                m["flesch_kincaid_grade"],
                label=f"Flesch-Kincaid grade <= {target_grade}",
                display_value="%.1f" % m["flesch_kincaid_grade"],
                max=target_grade,
            )
        )

        results.append(
            self._threshold_check(
                m["avg_words_per_sentence"],
                label="Average sentence length <= 20 words",
                display_value="%.1f" % m["avg_words_per_sentence"],
                max=20,
            )
        )

        results.append(
            self._threshold_check(
                m["long_sentence_ratio"],
                label="Long-sentence ratio <= 15%",
                display_value=self._percent(m["long_sentence_ratio"]),
                max=0.15,
            )
        )

        results.append(
            self._threshold_check(
                m["long_paragraph_ratio"],
                label="Long-paragraph ratio <= 20%",
                display_value=self._percent(m["long_paragraph_ratio"]),
                max=0.20,
            )
        )

        results.append(
            self._threshold_check(
                m["first_paragraph_words"],
                label="Lead paragraph <= 60 words",
                display_value=str(m["first_paragraph_words"]),
                max=60,
                warning_max=90,
            )
        )

        if m["words"] >= 600:
            minimum_headings = math.ceil(m["words"] / 300.0)
            results.append(
                self._threshold_check(
                    m["heading_count"],
                    label="Heading density (>= 1 heading / 300 words)",
                    display_value=f"{m['heading_count']} headings for {m['words']} words",
                    min=minimum_headings,
                )
            )

        if m["words"] >= 400:
            results.append(
                self._threshold_check(
                    m["list_item_count"],
                    label="At least one bulleted or numbered list for long content",
                    display_value=str(m["list_item_count"]),
                    min=1,
                )
            )

        return results

    # --- normalization --------------------------------------------------
    def _normalize_text(self, text):
        cleaned = text
        cleaned = self._strip_markdown_code_blocks(cleaned)
        cleaned = self._strip_html_code_blocks(cleaned)
        cleaned = self._strip_html_tags(cleaned)
        return re.sub(r"\r\n?", "\n", cleaned)

    def _strip_markdown_code_blocks(self, text):
        text = re.sub(r"```.*?```", "", text, flags=re.DOTALL)
        return re.sub(r"^ {4}.*$", "", text, flags=re.MULTILINE)

    def _strip_html_code_blocks(self, text):
        text = re.sub(r"<pre\b.*?</pre>", " ", text, flags=re.IGNORECASE | re.DOTALL)
        return re.sub(r"<code\b.*?</code>", " ", text, flags=re.IGNORECASE | re.DOTALL)

    def _strip_html_tags(self, text):
        return re.sub(r"<[^>]+>", " ", text)

    # --- extraction -----------------------------------------------------
    def _extract_words(self, text):
        return re.findall(r"[A-Za-z0-9']+", text)

    def _extract_sentences(self, text):
        joined = re.sub(r"\n+", " ", text)
        sentences = [s.strip() for s in re.split(r"(?<=[.!?])\s+", joined)]
        sentences = [s for s in sentences if s]
        return sentences if sentences else [text]

    def _extract_paragraphs(self, text):
        paragraphs = [p.strip() for p in re.split(r"\n\s*\n+", text)]
        paragraphs = [p for p in paragraphs if p]
        return paragraphs if paragraphs else [text]

    def _heading_count(self, text):
        markdown = len(re.findall(r"^\s{0,3}#{1,6}\s+.+$", text, flags=re.MULTILINE))
        html = len(re.findall(r"<h[1-6][^>]*>", text, flags=re.IGNORECASE))
        return markdown + html

    def _list_item_count(self, text):
        markdown = len(
            re.findall(r"^\s*(?:[-*+]\s+|\d+[.)]\s+)", text, flags=re.MULTILINE)
        )
        html = len(re.findall(r"<li\b", text, flags=re.IGNORECASE))
        return markdown + html

    # --- scoring --------------------------------------------------------
    def _flesch_kincaid_grade(self, words, sentences):
        word_count = len(words)
        if word_count == 0:
            return 0.0

        syllable_count = sum(self._count_syllables(word) for word in words)
        sentence_count = max(len(sentences), 1)

        return (
            0.39 * (word_count / sentence_count)
            + 11.8 * (syllable_count / word_count)
            - 15.59
        )

    def _count_syllables(self, word):
        token = re.sub(r"[^a-z]", "", word.lower())
        if not token:
            return 0
        if not (re.search(r"le$", token) and len(token) > 2):
            token = re.sub(r"e$", "", token)
        groups = len(re.findall(r"[aeiouy]+", token))
        return max(groups, 1)

    def _average(self, values):
        if not values:
            return 0.0
        return sum(values) / len(values)

    def _ratio(self, numerator, denominator):
        if not denominator:
            return 0.0
        return numerator / denominator

    def _percent(self, value):
        return "%.1f%%" % (value * 100)

    def _threshold_check(
        self, metric_value, label, display_value, min=None, max=None, warning_max=None
    ):
        if min is not None and float(metric_value) < float(min):
            return CheckResult("fail", label, f"{display_value} (minimum {min})")

        if max is not None and float(metric_value) > float(max):
            status = (
                "warn"
                if warning_max is not None and float(metric_value) <= float(warning_max)
                else "fail"
            )
            return CheckResult(status, label, f"{display_value} (maximum {max})")

        return CheckResult("pass", label, display_value)


def usage_error(message):
    print(message, file=sys.stderr)
    print(
        "Usage: readability_audit.py <file> [--branch BRANCH] [--target-grade N]",
        file=sys.stderr,
    )
    sys.exit(1)


def main(argv):
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("file", nargs="?")
    parser.add_argument("--branch")
    parser.add_argument("--target-grade", type=float, default=10.0)
    options = parser.parse_args(argv)

    file = options.file
    if file is None:
        usage_error("Missing file path")
    if not Path(file).exists():
        usage_error(f"File not found: {file}")

    text = Path(file).read_text()
    audit = ReadabilityAudit(text)
    metrics = audit.metrics()
    checks = audit.checks(target_grade=options.target_grade)

    print(f"Readability audit: {file}")
    print()
    print("Metrics")
    print(f"  Words: {metrics['words']}")
    print(f"  Sentences: {metrics['sentences']}")
    print(f"  Paragraphs: {metrics['paragraphs']}")
    print("  Flesch-Kincaid grade: %.1f" % metrics["flesch_kincaid_grade"])
    print("  Avg words/sentence: %.1f" % metrics["avg_words_per_sentence"])
    print("  Avg words/paragraph: %.1f" % metrics["avg_words_per_paragraph"])
    print(
        f"  Long sentences (>{LONG_SENTENCE_WORDS} words): "
        + ("%.1f%%" % (metrics["long_sentence_ratio"] * 100))
    )
    print(
        f"  Long paragraphs (>{LONG_PARAGRAPH_WORDS} words): "
        + ("%.1f%%" % (metrics["long_paragraph_ratio"] * 100))
    )
    print(f"  Headings: {metrics['heading_count']}")
    print(f"  List items: {metrics['list_item_count']}")
    print()
    print("Checks")

    status_labels = {"pass": "PASS", "warn": "WARN", "fail": "FAIL"}
    for check in checks:
        print(f"  [{status_labels[check.status]}] {check.label} — {check.details}")

    if options.branch:
        result = subprocess.run(
            ["git", "show", f"{options.branch}:{file}"],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0 and result.stdout.strip():
            baseline = ReadabilityAudit(result.stdout).metrics()
            print()
            print(f"Comparison to {options.branch}")
            print(
                "  Grade change: %+.1f"
                % (metrics["flesch_kincaid_grade"] - baseline["flesch_kincaid_grade"])
            )
            print(
                "  Sentence-length change: %+.1f words"
                % (
                    metrics["avg_words_per_sentence"]
                    - baseline["avg_words_per_sentence"]
                )
            )
            print(
                "  Long-sentence change: %+.1f%%"
                % (
                    (metrics["long_sentence_ratio"] - baseline["long_sentence_ratio"])
                    * 100
                )
            )
            print(
                "  Long-paragraph change: %+.1f%%"
                % (
                    (metrics["long_paragraph_ratio"] - baseline["long_paragraph_ratio"])
                    * 100
                )
            )
        else:
            print()
            print(f"Comparison skipped: could not read {file} from {options.branch}")

    sys.exit(2 if any(check.status == "fail" for check in checks) else 0)


if __name__ == "__main__":
    main(sys.argv[1:])
