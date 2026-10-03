#!/usr/bin/env python3
"""Refuses a public issue template that prompts for content the disclosure rule forbids.

This repository's public intake surface is its `.github/ISSUE_TEMPLATE/*.yml` files. Each
one renders, on GitHub, into a form a contributor fills in to open an issue; the answers
go straight into the issue body, which is published as soon as the issue is filed. The
disclosure rule in `Docs/agents/public-boundary.md` already polices commits and pull requests, but it cannot
reach the contributor inside the form — by the time a maintainer sees the answer, it is
already a published page on a public repository.

So the check has to live in the form. It reads every template, looks at every textarea
and input field's label, description and placeholder, and refuses any phrase that asks
the contributor for identifying detail of another product — a name ("other apps", "what
tools do you use", "current alternatives"), a quote, a screenshot, a link, pricing, or a
description that would pin the product. A name is one way to identify another dictation
product; a verbatim quote, a screenshot from the product, a link to its docs, the price
the contributor paid, or a paragraph describing its features are five more.

The rule is not that the form may not mention another product; it is that the form must
not *ask for one*. A field whose label says "What you do today" and whose description says
"the capability or workflow you reach for" passes: the contributor can write "I use a
separate text-expansion tool" or "I type it by hand", both of which are generic. A field
whose description says "Including other apps" fails: a reasonable contributor reads it
and writes a product name, and the form has now handed the rule a problem before a
maintainer saw it. The patterns are conservative about *the contributor's own* data —
"paste the error message" or "attach a screenshot of the problem" does not trip the
audit, because those ask about the contributor's bug, not another product.

The audit also requires a publication warning near any field whose id asks what the
contributor does today, so the rule reaches them at the moment they are about to write.

The template format is a constrained slice of YAML, and a full parser would pull a
runtime dependency into every gate run. The script reads the YAML line by line, picking
out the keys it cares about (`type`, `id`, `attributes.{label,description,placeholder,
value}`) by indentation, which is the only part of the format the form uses.
"""

import argparse
import os
import re
import sys

TEMPLATES_DIR = ".github/ISSUE_TEMPLATE"

# Phrases that ask the contributor to name another product. Each matches inside a single
# sentence, because the matches are reported with the surrounding text as the location.
INVITING = (
    re.compile(r"\bother apps?\b", re.IGNORECASE),
    re.compile(r"\bapps?\s+(?:you|that|which|i\s+use|i\s+have)\b", re.IGNORECASE),
    re.compile(r"\bapps?\s+do\s+you\b", re.IGNORECASE),
    re.compile(r"\bapps?\s+currently\b", re.IGNORECASE),
    re.compile(r"\bwhat apps?\b", re.IGNORECASE),
    re.compile(r"\btools?\s+(?:you|that|which|i\s+use|i\s+have)\b", re.IGNORECASE),
    re.compile(r"\btools?\s+do\s+you\b", re.IGNORECASE),
    re.compile(r"\btools?\s+currently\b", re.IGNORECASE),
    re.compile(r"\bsoftware\s+you\b", re.IGNORECASE),
    re.compile(r"\bsoftware\s+do\s+you\b", re.IGNORECASE),
    re.compile(r"\bproducts?\s+(?:you|that|which)\b", re.IGNORECASE),
    re.compile(r"\balternative apps?\b", re.IGNORECASE),
    re.compile(r"\bcurrent alternatives?\b", re.IGNORECASE),
    re.compile(r"\bwhat alternatives?\b", re.IGNORECASE),
    re.compile(r"\bcompetitors?\b", re.IGNORECASE),
)

# Phrases that ask the contributor for identifying detail of another product beyond its
# name: a quote, a screenshot, a link, pricing, or a description that would pin the
# product. The disclosure rule applies to anything that would let a reader identify
# another dictation product — a name is one way, but a verbatim quote, a screenshot
# from the product, a link to its docs, the price the contributor paid, or a paragraph
# describing its features are five more.
#
# Each pattern requires an explicit reference to another product: a possessive
# ("its", "their"), an "other"/"another" word, or "the/that" followed by a product
# noun ("app", "tool", "product", "software", "service"). A bare "the" with no product
# noun ("a screenshot of the bug", "a screenshot of the problem") does not match, so a
# bug report asking for the contributor's own evidence does not trip the audit.
IDENTIFYING = (
    # Quotes from or about another product.
    re.compile(r"\bquotes?\s+(?:from|of|about)\s+(?:another|other)\b", re.IGNORECASE),
    re.compile(r"\bquotes?\s+(?:from|of|about)\s+(?:the|that)\s+(?:other|product|app|tool|software|service)\b", re.IGNORECASE),
    re.compile(r"\bquotes?\s+(?:from|of|about)\s+(?:its|their)\b", re.IGNORECASE),
    re.compile(r"\bverbatim\s+(?:from|of|about)\s+(?:another|other)\b", re.IGNORECASE),
    re.compile(r"\bverbatim\s+(?:from|of|about)\s+(?:the|that)\s+(?:other|product|app|tool|software|service)\b", re.IGNORECASE),
    re.compile(r"\bverbatim\s+(?:from|of|about)\s+(?:its|their)\b", re.IGNORECASE),
    re.compile(r"\bexact\s+(?:text|words?|wording)\s+(?:from|of|about)\s+(?:another|other)\b", re.IGNORECASE),
    re.compile(r"\bexact\s+(?:text|words?|wording)\s+(?:from|of|about)\s+(?:the|that)\s+(?:other|product|app|tool|software|service)\b", re.IGNORECASE),
    re.compile(r"\bexact\s+(?:text|words?|wording)\s+(?:from|of|about)\s+(?:its|their)\b", re.IGNORECASE),
    # Screenshots, images, or recordings from another product.
    re.compile(r"\b(?:screenshot|screen\s+shot|screen\s+capture|screen\s+recording)s?\s+(?:of|from|about)\s+(?:another|other)\b", re.IGNORECASE),
    re.compile(r"\b(?:screenshot|screen\s+shot|screen\s+capture|screen\s+recording)s?\s+(?:of|from|about)\s+(?:the|that)\s+(?:other|product|app|tool|software|service)\b", re.IGNORECASE),
    re.compile(r"\b(?:screenshot|screen\s+shot|screen\s+capture|screen\s+recording)s?\s+(?:of|from|about)\s+(?:its|their)\b", re.IGNORECASE),
    re.compile(r"\battach\s+(?:a|the|their|its)\s+(?:screenshot|screen\s+shot|image|picture|photo|recording)s?\s+(?:of|from|about)\s+(?:another|other)\b", re.IGNORECASE),
    re.compile(r"\battach\s+(?:a|the|their|its)\s+(?:screenshot|screen\s+shot|image|picture|photo|recording)s?\s+(?:of|from|about)\s+(?:the|that)\s+(?:other|product|app|tool|software|service)\b", re.IGNORECASE),
    re.compile(r"\battach\s+(?:a|the|their|its)\s+(?:screenshot|screen\s+shot|image|picture|photo|recording)s?\s+(?:of|from|about)\s+(?:its|their)\b", re.IGNORECASE),
    re.compile(r"\binclude\s+(?:a|the|their|its)\s+(?:screenshot|screen\s+shot|image|picture|photo|recording)s?\s+(?:of|from|about)\s+(?:another|other)\b", re.IGNORECASE),
    re.compile(r"\binclude\s+(?:a|the|their|its)\s+(?:screenshot|screen\s+shot|image|picture|photo|recording)s?\s+(?:of|from|about)\s+(?:the|that)\s+(?:other|product|app|tool|software|service)\b", re.IGNORECASE),
    re.compile(r"\binclude\s+(?:a|the|their|its)\s+(?:screenshot|screen\s+shot|image|picture|photo|recording)s?\s+(?:of|from|about)\s+(?:its|their)\b", re.IGNORECASE),
    # Links and URLs to or from another product.
    re.compile(r"\b(?:link|url)s?\s+(?:to|from|of)\s+(?:another|other)\b", re.IGNORECASE),
    re.compile(r"\b(?:link|url)s?\s+(?:to|from|of)\s+(?:the|that)\s+(?:other|product|app|tool|software|service)\b", re.IGNORECASE),
    re.compile(r"\b(?:link|url)s?\s+(?:to|from|of)\s+(?:its|their)\b", re.IGNORECASE),
    re.compile(r"\bshare\s+(?:a|the|their|its)\s+(?:link|url)s?\s+(?:to|from|of)\s+(?:another|other)\b", re.IGNORECASE),
    re.compile(r"\bshare\s+(?:a|the|their|its)\s+(?:link|url)s?\s+(?:to|from|of)\s+(?:the|that)\s+(?:other|product|app|tool|software|service)\b", re.IGNORECASE),
    re.compile(r"\bshare\s+(?:a|the|their|its)\s+(?:link|url)s?\s+(?:to|from|of)\s+(?:its|their)\b", re.IGNORECASE),
    re.compile(r"\bpaste\s+(?:a|the|their|its)\s+(?:link|url)s?\s+(?:to|from|of)\s+(?:another|other)\b", re.IGNORECASE),
    re.compile(r"\bpaste\s+(?:a|the|their|its)\s+(?:link|url)s?\s+(?:to|from|of)\s+(?:the|that)\s+(?:other|product|app|tool|software|service)\b", re.IGNORECASE),
    re.compile(r"\bpaste\s+(?:a|the|their|its)\s+(?:link|url)s?\s+(?:to|from|of)\s+(?:its|their)\b", re.IGNORECASE),
    # Pricing of another product.
    re.compile(r"\bpricing\s+(?:of|for|in|from)\s+(?:another|other)\b", re.IGNORECASE),
    re.compile(r"\bpricing\s+(?:of|for|in|from)\s+(?:the|that)\s+(?:other|product|app|tool|software|service)\b", re.IGNORECASE),
    re.compile(r"\bpricing\s+(?:of|for|in|from)\s+(?:its|their)\b", re.IGNORECASE),
    re.compile(r"\b(?:price|cost|fee)s?\s+(?:of|for|in|from)\s+(?:another|other)\b", re.IGNORECASE),
    re.compile(r"\b(?:price|cost|fee)s?\s+(?:of|for|in|from)\s+(?:the|that)\s+(?:other|product|app|tool|software|service)\b", re.IGNORECASE),
    re.compile(r"\b(?:price|cost|fee)s?\s+(?:of|for|in|from)\s+(?:its|their)\b", re.IGNORECASE),
    re.compile(r"\bhow\s+much\s+(?:does|do|is|are)\s+(?:it|they|the\s+other)\b", re.IGNORECASE),
    # Identifying descriptions of another product.
    re.compile(r"\bdescribe\s+(?:the|that)\s+(?:other|product|app|tool|software|service)\b", re.IGNORECASE),
    re.compile(r"\bdescribe\s+(?:another|other)\s+(?:product|app|tool|software|service)\b", re.IGNORECASE),
    re.compile(r"\bdescribe\s+(?:its|their)\b", re.IGNORECASE),
    re.compile(r"\bfeatures?\s+(?:of|in|for)\s+(?:another|other)\b", re.IGNORECASE),
    re.compile(r"\bfeatures?\s+(?:of|in|for)\s+(?:the|that)\s+(?:other|product|app|tool|software|service)\b", re.IGNORECASE),
    re.compile(r"\bfeatures?\s+(?:of|in|for)\s+(?:its|their)\b", re.IGNORECASE),
    re.compile(r"\bproduct\s+description\s+(?:of|for)\s+(?:another|other)\b", re.IGNORECASE),
    re.compile(r"\bproduct\s+description\s+(?:of|for)\s+(?:the|that)\s+(?:other|product|app|tool|software|service)\b", re.IGNORECASE),
    re.compile(r"\bproduct\s+description\s+(?:of|for)\s+(?:its|their)\b", re.IGNORECASE),
    re.compile(r"\bwhat\s+(?:it|they)\s+(?:do|does|offer|provides?)\b", re.IGNORECASE),
)

# A field whose id asks what the contributor does today needs a publication warning
# beside it: the rule reaches the contributor at the moment they are about to write,
# not after the issue is filed.
WORKFLOW_FIELDS = re.compile(
    r"\b(?:alternative|alternatives|instead|currently|today|workflow)\b", re.IGNORECASE
)

# Phrases that mark a markdown block as a publication warning. The wording can vary, but
# the content must reach the rule in plain language, so the list is the bar rather than
# a precise script: anything that says "may not be published", "do not name", "do not
# publish" or similar lands here.
WARNING = (
    re.compile(r"\bpublication note\b", re.IGNORECASE),
    re.compile(r"\bmay not be published\b", re.IGNORECASE),
    re.compile(
        r"\bdo not (?:name|publish|describe|include|quote|screenshot|link)\b",
        re.IGNORECASE,
    ),
    re.compile(r"\bno (?:screenshots?|links?|quotes?|pricing|names?)\b", re.IGNORECASE),
    re.compile(r"\bidentifying detail\b", re.IGNORECASE),
    re.compile(r"\bdisclosure rule\b", re.IGNORECASE),
)

# YAML extraction. The format used by every template here is a list of body items, each
# with a `type`, an optional `id`, and an `attributes` map. Within `attributes`, the keys
# we care about are `label`, `description`, `placeholder` and `value` (the last for
# `markdown` blocks). A multi-line value is a `|` block scalar, indented two spaces past
# its key. These patterns read the values as raw text — no parsing of escapes or nested
# types — because the audit only inspects strings.

FIELD_TYPES = ("textarea", "input")

KEY_VALUE = re.compile(r"^(\s*)([a-zA-Z_][a-zA-Z0-9_]*):\s*(.*)$")
BLOCK_SCALAR = re.compile(r"^(\s*)([a-zA-Z_][a-zA-Z0-9_]*):\s*[|>][+-]?\s*$")


def read_text(path):
    """Yields (line_number, line_text) for the file at `path`."""
    with open(path, errors="ignore") as handle:
        for number, line in enumerate(handle, start=1):
            yield number, line.rstrip("\n")


def parse_yaml(path):
    """Yields one record per `body` item in the template, each a dict of fields.

    Records are returned in document order. A record without a `type` is skipped, as is
    one whose type is not `textarea`, `input` or `markdown` — the audit only inspects
    those three. Indentation-based parsing: a new top-level key (no leading whitespace)
    starts a new section, and a `body` section is the only one it reads.
    """
    in_body = False
    record = None
    block_key = None
    block_indent = None
    block_lines = []

    def close_block():
        nonlocal block_key, block_indent, block_lines
        if record is not None and block_key:
            record[block_key] = "\n".join(block_lines).rstrip()
        block_key = None
        block_indent = None
        block_lines = []

    def leading_spaces(text):
        return len(text) - len(text.lstrip(" "))

    for number, line in read_text(path):
        if not line.strip():
            continue
        indent = leading_spaces(line)
        if not in_body:
            if indent == 0 and line.startswith("body:"):
                in_body = True
            continue
        if indent == 0:
            # A new top-level key ends the body section.
            close_block()
            if record is not None:
                yield record
                record = None
            in_body = False
            continue
        # A new list item under `body:` starts a new record.
        if line.startswith("  - ") or (indent == 2 and line.startswith("- ")):
            close_block()
            if record is not None:
                yield record
            record = {"__line": number}
            tail = line.lstrip(" ")[2:]  # drop "- "
            if ":" in tail:
                key, _, value = tail.partition(":")
                record[key.strip()] = value.strip()
            continue
        # A key under the current list item, or nested under one of its keys.
        if indent in (4, 6):
            stripped = line.lstrip(" ")
            match = BLOCK_SCALAR.match(stripped)
            if match:
                close_block()
                block_key = match.group(2)
                block_indent = indent
                block_lines = []
                continue
            match = KEY_VALUE.match(stripped)
            if match and record is not None:
                close_block()
                key, value = match.group(2), match.group(3).strip()
                record[key] = value
                continue
        # Continuation of an indented block scalar. The scalar's content is indented
        # strictly past the key, and the parser collects lines until indentation drops
        # back to the key's level.
        if block_key is not None and indent > block_indent:
            block_lines.append(line[block_indent + 2:])
            continue
        # Anything else ends the current block scalar.
        close_block()
    close_block()
    if record is not None:
        yield record


def record_text(record, *keys):
    """Joins the named keys' values, skipping missing ones, for one audit decision."""
    parts = []
    for key in keys:
        value = record.get(key)
        if value:
            parts.append(value)
    return "\n".join(parts)


def field_text(record):
    """Every word a contributor reads before they fill in a textarea or input."""
    return record_text(record, "id", "label", "description", "placeholder")


def markdown_text(record):
    """The rendered markdown of a `type: markdown` block."""
    return record_text(record, "value")


def inviting_in(text):
    """Yields (category, phrase) for each pattern that matches, across both lists.

    A pattern is one of "inviting" (asks for a product name) or "identifying" (asks for
    a quote, screenshot, link, price, or identifying description of another product).
    The audit collects findings by category and reports each one.
    """
    seen = {"inviting": set(), "identifying": set()}
    for pattern in INVITING:
        match = pattern.search(text)
        if match and match.group(0).lower() not in seen["inviting"]:
            seen["inviting"].add(match.group(0).lower())
            yield "inviting", match.group(0)
    for pattern in IDENTIFYING:
        match = pattern.search(text)
        if match and match.group(0).lower() not in seen["identifying"]:
            seen["identifying"].add(match.group(0).lower())
            yield "identifying", match.group(0)


def warning_in(text):
    """True if any WARNING phrase matches in `text`."""
    return any(pattern.search(text) for pattern in WARNING)


def scan_template(path):
    """Yields (line, finding) for each violation in one template."""
    last_warning_line = 0
    for record in parse_yaml(path):
        kind = record.get("type")
        if kind == "markdown":
            value = markdown_text(record)
            if value and warning_in(value):
                last_warning_line = max(last_warning_line, record["__line"])
            continue
        if kind not in FIELD_TYPES:
            continue
        field_id = record.get("id") or "(unlabeled)"
        text = field_text(record)
        if not text:
            continue
        inviting_matches = []
        identifying_matches = []
        for category, phrase in inviting_in(text):
            if category == "inviting":
                inviting_matches.append(phrase)
            elif category == "identifying":
                identifying_matches.append(phrase)
        if inviting_matches:
            quoted = ", ".join(f"`{phrase}`" for phrase in inviting_matches)
            yield record["__line"], (
                f"field `{field_id}` invites product names ({quoted})"
            )
        if identifying_matches:
            quoted = ", ".join(f"`{phrase}`" for phrase in identifying_matches)
            yield record["__line"], (
                f"field `{field_id}` invites identifying detail of another product "
                f"({quoted})"
            )
        if kind == "textarea" and WORKFLOW_FIELDS.search(field_id):
            if last_warning_line == 0:
                yield record["__line"], (
                    f"field `{field_id}` asks what the contributor does today "
                    "but the template has no publication warning above it"
                )


def scan_tree():
    """Returns the list of (path, line, finding) for every template under templates dir."""
    if not os.path.isdir(TEMPLATES_DIR):
        return [(TEMPLATES_DIR, 0, f"`{TEMPLATES_DIR}` is not a directory in this tree")]
    findings = []
    for name in sorted(os.listdir(TEMPLATES_DIR)):
        if not name.endswith(".yml"):
            continue
        path = os.path.join(TEMPLATES_DIR, name)
        if not os.path.isfile(path):
            continue
        for line, finding in scan_template(path):
            findings.append((path, line, finding))
    return findings


def report(findings):
    if not findings:
        return
    print("\n  ✗ an issue template invites content the disclosure rule forbids\n", file=sys.stderr)
    for path, line, finding in findings:
        location = f"{path}:{line}" if line else path
        print(f"    {location}  {finding}", file=sys.stderr)
    print(
        "\n    The disclosure rule applies to issues as well as commits. A contributor reading",
        file=sys.stderr,
    )
    print(
        "    the form answers the question they are asked; if the form asks for a product",
        file=sys.stderr,
    )
    print(
        "    name, a quote, a screenshot, a link, pricing, or a description that pins the",
        file=sys.stderr,
    )
    print(
        "    product, the answer is published before a maintainer sees it. Rephrase the",
        file=sys.stderr,
    )
    print(
        "    field in terms of the capability or workflow, and put a publication note above it.",
        file=sys.stderr,
    )
    print(
        "    See `Docs/agents/public-boundary.md`.",
        file=sys.stderr,
    )
    print("", file=sys.stderr)


def self_test():
    """Run invented templates through the scan; print any that misfire; return their count.

    Each fixture is written into the templates directory for the duration of the run,
    parsed by the same code path `make verify` will exercise, and removed afterwards.
    """
    fixtures = TEMPLATES_DIR
    wrong = 0
    for name, text, expected in SELF_TEST_FIXTURES:
        path = os.path.join(fixtures, name)
        with open(path, "w") as handle:
            handle.write(text)
        actual = len(list(scan_template(path)))
        if actual != expected:
            wrong += 1
            print(
                f"  ✗ self-test: {name} produced {actual} finding(s), expected {expected}",
                file=sys.stderr,
            )
        os.remove(path)
    return wrong


SELF_TEST_FIXTURES = (
    (
        "_audit_fixture_passing.yml",
        "name: passing\nbody:\n"
        "  - type: markdown\n"
        "    attributes:\n"
        "      value: |\n"
        "        **Publication note.** What you write here is published.\n"
        "  - type: textarea\n"
        "    id: alternatives\n"
        "    attributes:\n"
        "      label: What you do today\n"
        "      description: The capability or workflow you reach for.\n",
        0,
    ),
    (
        "_audit_fixture_other_apps.yml",
        "name: failing\nbody:\n"
        "  - type: textarea\n"
        "    id: alternatives\n"
        "    attributes:\n"
        "      label: What you do instead today\n"
        "      description: Including other apps. Knowing what already works is useful.\n",
        2,
    ),
    (
        "_audit_fixture_what_apps.yml",
        "name: failing\nbody:\n"
        "  - type: textarea\n"
        "    id: tools\n"
        "    attributes:\n"
        "      label: Tools\n"
        "      description: What apps do you use?\n",
        1,
    ),
    (
        "_audit_fixture_no_warning.yml",
        "name: failing\nbody:\n"
        "  - type: textarea\n"
        "    id: alternatives\n"
        "    attributes:\n"
        "      label: What you do instead today\n"
        "      description: The capability or workflow you reach for.\n",
        1,
    ),
    (
        "_audit_fixture_bug_report.yml",
        "name: bug\nbody:\n"
        "  - type: textarea\n"
        "    id: anything-else\n"
        "    attributes:\n"
        "      label: Anything else\n"
        "      description: Console output, a screen recording, whatever you have.\n",
        0,
    ),
    # Negative cases for the new identifying-detail patterns. Each fixture adds one
    # of the categories the maintainer asked the audit to cover: quote, screenshot,
    # link, pricing, or identifying description of another product. The wording is
    # chosen so it does NOT also trip the inviting patterns — only the new ones —
    # so the expected finding count is exactly the one new match plus the workflow-
    # field-missing-warning match.
    (
        "_audit_fixture_quote.yml",
        "name: quote\nbody:\n"
        "  - type: textarea\n"
        "    id: alternatives\n"
        "    attributes:\n"
        "      label: Verbatim\n"
        "      description: Verbatim from the other would help here.\n",
        2,
    ),
    (
        "_audit_fixture_screenshot.yml",
        "name: screenshot\nbody:\n"
        "  - type: textarea\n"
        "    id: alternatives\n"
        "    attributes:\n"
        "      label: Capture\n"
        "      description: A screen capture of the other would help here.\n",
        2,
    ),
    (
        "_audit_fixture_link.yml",
        "name: link\nbody:\n"
        "  - type: textarea\n"
        "    id: alternatives\n"
        "    attributes:\n"
        "      label: Reference\n"
        "      description: A link to the other would help here.\n",
        2,
    ),
    (
        "_audit_fixture_pricing.yml",
        "name: pricing\nbody:\n"
        "  - type: textarea\n"
        "    id: alternatives\n"
        "    attributes:\n"
        "      label: Cost\n"
        "      description: The cost of the other would help here.\n",
        2,
    ),
    (
        "_audit_fixture_features.yml",
        "name: features\nbody:\n"
        "  - type: textarea\n"
        "    id: alternatives\n"
        "    attributes:\n"
        "      label: Capabilities\n"
        "      description: Describe the features of the other, if you can.\n",
        2,
    ),
    # The contributor's own data must not trip the audit. These are the kinds of
    # prompts a bug report legitimately asks for.
    (
        "_audit_fixture_own_data.yml",
        "name: own-data\nbody:\n"
        "  - type: textarea\n"
        "    id: repro-steps\n"
        "    attributes:\n"
        "      label: Steps to reproduce\n"
        "      description: |\n"
        "        1. Hold the dictation key.\n"
        "        2. Say hello.\n"
        "        3. Paste the error message here.\n"
        "      placeholder: Attach a screenshot if you can.\n",
        0,
    ),
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="prove the audit reports each invented violation exactly when expected",
    )
    options = parser.parse_args()

    if options.self_test:
        wrong = self_test()
        if wrong:
            print(
                f"\nissue template audit: self-test failed on {wrong} fixture(s); the audit"
                "\nis no longer reporting what it should. Fix the audit.\n",
                file=sys.stderr,
            )
            return 1
        print("\nissue template audit: self-test passed on every fixture.\n")
        return 0

    findings = scan_tree()
    if findings:
        report(findings)
        return 1
    templates = [
        name
        for name in sorted(os.listdir(TEMPLATES_DIR))
        if name.endswith(".yml") and os.path.isfile(os.path.join(TEMPLATES_DIR, name))
    ]
    print(
        f"\n  ✓ {len(templates)} issue template(s); none invite content the disclosure rule forbids"
    )
    print("    every textarea and input asks for the capability or workflow, not the product")
    return 0


if __name__ == "__main__":
    sys.exit(main())