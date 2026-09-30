#!/usr/bin/env python3
"""Proves the preview helper ignores unrelated image files and embeds referenced ones."""
import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

PACKAGE_ROOT = Path(__file__).resolve().parent.parent
PREVIEW_SCRIPT = PACKAGE_ROOT / "Design" / "_preview_gen.py"
SPEC = importlib.util.spec_from_file_location("preview_gen", PREVIEW_SCRIPT)
PREVIEW = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PREVIEW)


def artboard(image_markup=""):
    return (
        "<html><head><style>.stage { color: black; }</style></head><body><x-dc>"
        f'<div class="stage">{image_markup}</div>\n</x-dc></body></html>'
    )


class FakeImage:
    LANCZOS = object()

    def __init__(self):
        self.closed = False
        self.thumbnail_size = None
        self.open_count = 0

    def open(self, path):
        self.opened_path = path
        self.open_count += 1
        return self

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.closed = True

    def thumbnail(self, size, _resample):
        self.thumbnail_size = size

    def save(self, buffer, format_name):
        self.format_name = format_name
        buffer.write(b"thumbnail-bytes")


class PreviewGeneratorTests(unittest.TestCase):
    def test_unreferenced_malformed_png_is_ignored_without_pillow(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Identity.dc.html").write_text(artboard())
            (root / "broken.png").write_bytes(b"not a PNG")
            first = subprocess.run(
                [sys.executable, "-S", str(PREVIEW_SCRIPT), "Identity"],
                cwd=root,
                capture_output=True,
                text=True,
            )
            self.assertEqual(first.returncode, 0, first.stderr)
            output = (root / "_preview.html").read_bytes()
            second = subprocess.run(
                [sys.executable, "-S", str(PREVIEW_SCRIPT), "Identity"],
                cwd=root,
                capture_output=True,
                text=True,
            )
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertEqual((root / "_preview.html").read_bytes(), output)
            self.assertNotIn(b"data:image/png", output)

    def test_referenced_png_is_inlined_and_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            markup = artboard(
                '<img src="./logo.png?v=1">'
                '<div style="background:url(logo.png#hash)"></div>'
                '<img src="https://cdn.example.test/remote.png?v=2">'
            )
            (root / "Identity.dc.html").write_text(markup)
            (root / "logo.png").write_bytes(b"PNG fixture")
            image = FakeImage()
            html = PREVIEW.preview_html("Identity", root, image=image)
            expected_uri = "data:image/png;base64,dGh1bWJuYWlsLWJ5dGVz"
            self.assertEqual(html.count(expected_uri), 2)
            self.assertNotIn("?v=1", html)
            self.assertNotIn("#hash", html)
            self.assertIn('src="https://cdn.example.test/remote.png?v=2"', html)
            self.assertEqual(image.opened_path, root / "./logo.png")
            self.assertEqual(image.open_count, 1)
            self.assertEqual(image.thumbnail_size, (256, 256))
            self.assertEqual(image.format_name, "PNG")
            self.assertTrue(image.closed)

    def test_referenced_png_without_pillow_has_actionable_error(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Identity.dc.html").write_text(artboard('<img src="logo.png">'))
            result = subprocess.run(
                [sys.executable, "-S", str(PREVIEW_SCRIPT), "Identity"],
                cwd=root,
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("python3 -m pip install Pillow", result.stderr)
            self.assertIn("artboard references a PNG", result.stderr)

    def test_remote_png_reference_stays_external_without_pillow(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            remote = 'https://cdn.example.test/logo.png?v=1#preview'
            (root / "Identity.dc.html").write_text(
                artboard(f'<img src="{remote}">')
            )
            result = subprocess.run(
                [sys.executable, "-S", str(PREVIEW_SCRIPT), "Identity"],
                cwd=root,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            output = (root / "_preview.html").read_text()
            self.assertIn(f'src="{remote}"', output)
            self.assertNotIn("data:image/png", output)


if __name__ == "__main__":
    unittest.main()
