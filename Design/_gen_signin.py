"""Update only the offered-provider stack on the four sign-in artboards.

The sign-in window has its own compact chrome. Its shared shell generator also
builds the main window, so rebuilding a whole sign-in page can pull unrelated
main-window changes into these references. This generator patches the provider
stack and its provider-specific caption while preserving the rest of each page.
"""

from pathlib import Path
import re

from _gen_shell import apple_mark, github_mark, google_mark
from _signin_contract import offered_providers


ARTBOARD_DIR = Path(__file__).resolve().parent
ARTBOARDS = (
    ("Sign-In.dc.html", False),
    ("Sign-In-Dark.dc.html", False),
    ("Sign-In-Offline.dc.html", True),
    ("Sign-In-Offline-Dark.dc.html", True),
)
STACK = re.compile(
    r'^(?P<opening>[ \t]*<div class="stack">)[^\n]*\n'
    r".*?^(?P<closing>[ \t]*</div>)",
    re.M | re.S,
)
CAPTION = re.compile(r'<div class="caption">.*?</div>', re.S)
CAPTIONS = {
    False: (
        '<div class="caption">The first screen anyone sees, and step 1 of 7. There is no '
        '&ldquo;continue without an account&rdquo;: signing in is required, and nothing on '
        'this screen hints otherwise. What the screen owes the user in exchange is the '
        'plain statement that this is the only moment Uttrflow needs a network. The Google '
        'mark here is a stand-in and must be replaced by its supplied file in a shipped '
        'button.</div>'
    ),
    True: (
        '<div class="caption">Offline, the screen says exactly which step needs the network '
        'and does not pretend a way through. The Google button stays visible but inert, so '
        'it is obvious what will happen the moment the connection returns.</div>'
    ),
}


def provider_button(provider, title, disabled):
    """Keep the provider's existing mark and brand treatment in the compact stack."""
    if provider == "google":
        style, mark = " google", google_mark(18)
    elif provider == "gitHub":
        style, mark = "", github_mark(17)
    elif provider == "apple":
        style, mark = " apple", apple_mark(17)
    else:
        raise RuntimeError(f"no sign-in artboard treatment for offered provider {provider!r}")
    dim = ' style="opacity: 0.38"' if disabled else ""
    return (
        f'<div class="provbtn{style}" data-provider="{provider}"{dim}>'
        f'{mark}<span>{title}</span></div>'
    )


def update_artboard(path, disabled):
    """Replace only the provider stack and its caption in one committed artboard."""
    html = path.read_text()
    stack_match = STACK.search(html)
    caption_match = CAPTION.search(html)
    if not stack_match or not caption_match:
        raise RuntimeError(f"could not find the sign-in provider stack and caption in {path}")
    buttons = "\n        ".join(
        provider_button(provider, title, disabled)
        for provider, title in offered_providers()
    )
    replacement = (
        f'{stack_match.group("opening")}\n        {buttons}\n'
        f'{stack_match.group("closing")}'
    )
    html = STACK.sub(replacement, html, count=1)
    html = CAPTION.sub(CAPTIONS[disabled], html, count=1)
    path.write_text(html)


def main():
    for name, disabled in ARTBOARDS:
        update_artboard(ARTBOARD_DIR / name, disabled)
    print(f"updated provider stacks in {len(ARTBOARDS)} sign-in artboards")


if __name__ == "__main__":
    main()
