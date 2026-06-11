#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Flesch-Kincaid Grade Level Calculator.

Usage: flesch_kincaid.py [filename] [branch]
  - no arguments: reads from STDIN
  - filename only: analyzes that file
  - filename and branch: compares current file to the version in branch
"""

import re
import sys

from readability_cli import ReadabilityCli


class FleschKincaidCalculator:
    def grade_level(self, text):
        words = self._words_in(self._strip_code_blocks(text))
        if not words:
            return 0.0
        return self._grade_formula(
            self._words_per_sentence(words, text),
            self._syllables_per_word(words),
        )

    def _strip_code_blocks(self, text):
        return re.sub(r"```.*?```", "", text, flags=re.DOTALL)

    def _words_in(self, text):
        cleaned = (re.sub(r"[^a-zA-Z]", "", word) for word in text.split())
        return [word for word in cleaned if word]

    def _sentence_count(self, text):
        return max(len(re.findall(r"[.!?]+", text)), 1)

    def _words_per_sentence(self, words, text):
        return len(words) / self._sentence_count(text)

    def _syllables_per_word(self, words):
        return self._syllable_count(words) / len(words)

    def _grade_formula(self, words_per_sentence, syllables_per_word):
        return 0.39 * words_per_sentence + 11.8 * syllables_per_word - 15.59

    def _syllable_count(self, words):
        return sum(self._syllables_in(word) for word in words)

    def _syllables_in(self, word):
        token = re.sub(r"[^a-z]", "", word.lower())
        if not token:
            return 0
        if not (re.search(r"le$", token) and len(token) > 2):
            token = re.sub(r"e$", "", token)
        return max(len(re.findall(r"[aeiouy]+", token)), 1)


class FleschKincaidCli(ReadabilityCli):
    def __init__(self, argv, stdin):
        super().__init__(argv, stdin)
        self._calculator = FleschKincaidCalculator()

    def analyze(self, text):
        return self._calculator.grade_level(text)

    def print_current(self, grade):
        print("Flesch-Kincaid Grade Level: %.1f" % grade)

    def comparison_title(self):
        return "Flesch-Kincaid Grade Level Comparison"

    def comparison_delta(self, baseline, current):
        return baseline - current

    def output_format(self):
        return "%.1f"


if __name__ == "__main__":
    FleschKincaidCli(sys.argv[1:], sys.stdin).run()
