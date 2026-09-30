#!/usr/bin/env python3
"""Keep every sign-in artboard aligned with the providers production offers."""

import argparse
from html import unescape
import os
import re
import sys


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "Design"))
from _signin_contract import offered_providers  # noqa: E402


ARTBOARDS = (
    "Sign-In.dc.html",
    "Sign-In-Dark.dc.html",
    "Sign-In-Offline.dc.html",
    "Sign-In-Offline-Dark.dc.html",
)
PROVIDER_BUTTON = re.compile(
    r'<div class="provbtn[^\"]*" data-provider="([^\"]+)"[^>]*>'
    r".*?<span>(.*?)</span></div>",
    re.S,
)


def buttons_in(text):
    return [(provider, unescape(title).strip()) for provider, title in PROVIDER_BUTTON.findall(text)]


def failures(expected, actual):
    if actual == expected:
        return []
    return [f"expected {expected!r}, found {actual!r}"]


def audit():
    expected = offered_providers()
    errors = []
    for name in ARTBOARDS:
        path = os.path.join(ROOT, "Design", name)
        if not os.path.isfile(path):
            errors.append(f"{name}: artboard is missing")
            continue
        actual = buttons_in(open(path).read())
        errors.extend(f"{name}: {message}" for message in failures(expected, actual))
    return errors


def self_test():
    expected = [("google", "Continue with Google")]
    fixtures = [
        (expected, []),
        ([("google", "Continue with Google"), ("apple", "Sign in with Apple")], ["provider drift"]),
        ([("google", "Sign in with Google")], ["title drift"]),
        ([], ["missing button"]),
    ]
    for actual, expected_failure in fixtures:
        messages = failures(expected, actual)
        if bool(messages) != bool(expected_failure):
            print(f"  ✗ self-test: expected {expected_failure!r}, got {messages!r}", file=sys.stderr)
            return False
    sample = (
        '<div class="provbtn google" data-provider="google">'
        '<svg aria-label="Google"></svg><span>Continue with Google</span></div>'
    )
    if buttons_in(sample) != expected:
        print("  ✗ self-test: provider button extraction failed", file=sys.stderr)
        return False
    print("signin artboard contract audit: self-test passed")
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test and not self_test():
        return 1
    errors = audit()
    if errors:
        print("signin artboard contract audit: FAILED", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1
    providers = ", ".join(provider for provider, _ in offered_providers())
    print(f"signin artboard contract audit: all four variants offer {providers}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
