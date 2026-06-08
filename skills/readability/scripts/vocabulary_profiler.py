#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Vocabulary Profiler.

Usage: vocabulary_profiler.py [filename] [branch]
  - no arguments: reads from STDIN
  - filename only: analyzes that file
  - filename and branch: compares current file to the version in branch
Word list from: https://simple.wikipedia.org/wiki/Wikipedia:List_of_1000_basic_words
"""

import re
import sys
from pathlib import Path

from readability_cli import ReadabilityCli


class VocabularyProfiler:
    def __init__(self, word_list_path):
        self._basic_words = frozenset(Path(word_list_path).read_text().splitlines())

    def top1000_percentage(self, text):
        words = self._extract_words(self._strip_code_blocks(text))
        if not words:
            return 0.0
        basic_words = sum(1 for word in words if word in self._basic_words)
        return basic_words / len(words) * 100

    def _strip_code_blocks(self, text):
        return re.sub(r"```.*?```", "", text, flags=re.DOTALL)

    def _extract_words(self, text):
        return re.findall(r"[a-z]+", text.lower())


class VocabularyProfilerCli(ReadabilityCli):
    WORD_LIST_PATH = Path(__file__).resolve().parent / "top1000.txt"

    def __init__(self, argv, stdin):
        super().__init__(argv, stdin)
        self._profiler = VocabularyProfiler(self.WORD_LIST_PATH)

    def analyze(self, text):
        return self._profiler.top1000_percentage(text)

    def print_current(self, percentage):
        print("Words in top 1000: %.1f%%" % percentage)

    def comparison_title(self):
        return "Top 1000 Words Comparison"

    def output_format(self):
        return "%.1f%%"


if __name__ == "__main__":
    VocabularyProfilerCli(sys.argv[1:], sys.stdin).run()
