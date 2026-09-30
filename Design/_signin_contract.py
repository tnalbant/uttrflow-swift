"""Read the deployed sign-in choices and labels from the account model."""

from pathlib import Path
import re


ACCOUNT_SOURCE = (
    Path(__file__).resolve().parent.parent
    / "Sources"
    / "UttrflowAccount"
    / "Account.swift"
)


def offered_providers():
    """Return (case, button title) pairs from SignInProvider's shipped contract."""
    text = ACCOUNT_SOURCE.read_text()
    offered = re.search(
        r"public static let offered: \[SignInProvider\] = \[(?P<cases>[^]]*)\]",
        text,
    )
    if not offered:
        raise RuntimeError(f"could not read SignInProvider.offered from {ACCOUNT_SOURCE}")
    cases = re.findall(r"\.([A-Za-z][A-Za-z0-9]*)", offered.group("cases"))
    if not cases:
        raise RuntimeError("SignInProvider.offered must contain at least one provider")

    titles = re.search(
        r"public var buttonTitle: String \{(?P<body>.*?)\n    \}", text, re.S
    )
    if not titles:
        raise RuntimeError(f"could not read SignInProvider.buttonTitle from {ACCOUNT_SOURCE}")
    title_by_case = dict(
        re.findall(r"case \.([A-Za-z][A-Za-z0-9]*):\s*\"([^\"]+)\"", titles.group("body"))
    )
    missing = [case for case in cases if case not in title_by_case]
    if missing:
        raise RuntimeError(f"offered sign-in providers have no button title: {missing}")
    if len(set(cases)) != len(cases):
        raise RuntimeError("SignInProvider.offered contains a duplicate provider")
    return [(case, title_by_case[case]) for case in cases]
