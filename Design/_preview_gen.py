"""Standalone render of an artboard, for eyeballing it outside the canvas host.

    python3 _preview_gen.py Identity   # -> _preview.html
"""
import argparse
import base64
import io
import re
from pathlib import Path

PNG_REFERENCE = re.compile(
    r'''(?:src\s*=\s*|url\(\s*)["']?
        (?P<path>(?:\./)?(?!/)(?!\.\./)(?![a-z][a-z0-9+.-]*:)[^"'()\s?#]+?\.png)
        (?P<suffix>[?#][^"')\s]*)?["']?''',
    re.IGNORECASE | re.VERBOSE,
)


def referenced_pngs(markup):
    """Returns PNG paths used by image sources in document order."""
    return list(dict.fromkeys(match.group("path") for match in PNG_REFERENCE.finditer(markup)))


def image_module():
    """Loads Pillow only when an artboard references a PNG."""
    try:
        from PIL import Image
    except ModuleNotFoundError as error:
        if error.name not in {"PIL", "PIL.Image"}:
            raise
        raise RuntimeError(
            "this artboard references a PNG, so thumbnailing needs Pillow; "
            "install it with `python3 -m pip install Pillow` and retry"
        ) from error
    return Image


def preview_html(name, design_dir, image=None):
    """Builds a standalone preview and inlines only its referenced PNGs."""
    source = (design_dir / f"{name}.dc.html").read_text()
    style = re.search(r"<style>(.*?)</style>", source, re.S).group(1)
    stage = re.search(r'(<div class="stage.*?)\n</x-dc>', source, re.S).group(1)
    html = f"<!doctype html><meta charset=\"utf-8\"><style>{style}</style>{stage}"
    pngs = referenced_pngs(html)
    if pngs and image is None:
        image = image_module()

    embedded = {}
    for reference in pngs:
        asset = reference.removeprefix("./")
        if asset in embedded:
            continue
        image_path = design_dir / asset
        with image.open(image_path) as opened:
            opened.thumbnail((256, 256), image.LANCZOS)
            buffer = io.BytesIO()
            opened.save(buffer, "PNG")
        embedded[asset] = "data:image/png;base64," + base64.b64encode(
            buffer.getvalue()
        ).decode()

    def inline(match):
        reference = match.group("path")
        uri = embedded[reference.removeprefix("./")]
        full_reference = reference + (match.group("suffix") or "")
        return match.group(0).replace(full_reference, uri, 1)

    return PNG_REFERENCE.sub(inline, html)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("name", nargs="?", default="Identity")
    args = parser.parse_args()
    design_dir = Path.cwd()
    try:
        html = preview_html(args.name, design_dir)
    except RuntimeError as error:
        parser.error(str(error))
    output = design_dir / "_preview.html"
    output.write_text(html)
    print(f"_preview.html <- {args.name} ({len(html) // 1024} KB)")


if __name__ == "__main__":
    main()
