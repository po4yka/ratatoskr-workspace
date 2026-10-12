"""Synthetic PDFs with a text layer for flow F2. usage: pdfs.py OUTDIR

Writes text-small.pdf (one page, one distinctive word), text-outage.pdf and text-bad-request.pdf (one distinctive word each, for the outage legs of F2), big-over.pdf and big-under.pdf. The extractor refuses to publish a Document IR whose event exceeds MAX_EVENT_BYTES (default 8,000,000, the broker's 8 MiB limit minus the envelope), so big-over.pdf carries about 8 MB of extracted text (above the event limit once the Document IR is serialised, and below the parser's own 8 MiB text budget, which a larger document would hit first and fail with content.extraction.failed) and big-under.pdf about 5 MB; the flow reports what the extractor really does with each. The no-text-layer case uses extractor/crates/pdf/tests/fixtures/no-text-layer.pdf from the pinned checkout. Pure standard library; the content is invented."""
import pathlib
import random
import sys

WORDS = ("harbour", "lantern", "meadow", "quartz", "tundra", "willow", "ember", "saffron", "glacier", "orchard", "cobalt", "fjord", "juniper", "pebble", "sundial", "thicket")


def pdf(pages: list[str]) -> bytes:
    """A minimal PDF 1.4 file: one Helvetica text object per line of every page."""
    objects: list[bytes] = []
    kids = " ".join(f"{4 + 2 * i} 0 R" for i in range(len(pages)))
    objects.append(b"<< /Type /Catalog /Pages 2 0 R >>")
    objects.append(f"<< /Type /Pages /Kids [{kids}] /Count {len(pages)} >>".encode())
    objects.append(b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
    for i, text in enumerate(pages):
        stream = ("BT /F1 10 Tf 12 TL 40 760 Td " + text + " ET").encode("latin-1")
        objects.append(f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents {5 + 2 * i} 0 R /Resources << /Font << /F1 3 0 R >> >> >>".encode())
        objects.append(b"<< /Length " + str(len(stream)).encode() + b" >>\nstream\n" + stream + b"\nendstream")
    out = bytearray(b"%PDF-1.4\n")
    offsets = []
    for number, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += f"{number} 0 obj\n".encode() + body + b"\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n".encode()
    for offset in offsets:
        out += f"{offset:010d} 00000 n \n".encode()
    out += f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    return bytes(out)


def lines_of(total_bytes: int, marker: str, seed: int) -> list[str]:
    """Pages of `(text) Tj T*` lines whose text adds up to about total_bytes."""
    rng = random.Random(seed)
    pages, size = [], 0
    while size < total_bytes:
        page = []
        for _ in range(150):
            line = " ".join(rng.choice(WORDS) for _ in range(12)) + f" {marker}"
            page.append(f"({line}) Tj T*")
            size += len(line) + 1
        pages.append(" ".join(page))
    return pages


out = pathlib.Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
def prose(word: str, topic: str) -> list[str]:
    """A short page of plain prose with enough words for the extractor's text-layer check (a one-line PDF is judged as having no text layer). `word` is the distinctive search term."""
    sentences = [
        f"{word} {topic} notes, first section.",
        f"The survey of the {topic} began on a cold morning and the team recorded every measurement by hand.",
        f"Each reading was checked twice before it was written into the shared notebook of the {word} project.",
        "Volunteers walked the northern boundary, then the eastern boundary, and compared their paper maps.",
        "By the afternoon the weather had improved, which made the remaining measurements considerably easier.",
        f"The final summary of the {word} {topic} survey lists the open questions for the next season.",
    ]
    return [" ".join(f"({sentence}) Tj T*" for sentence in sentences)]


(out / "text-small.pdf").write_bytes(pdf(prose("Chartreuse", "lantern")))
(out / "text-outage.pdf").write_bytes(pdf(prose("Persimmon", "orchard")))
(out / "text-bad-request.pdf").write_bytes(pdf(prose("Mulberry", "trellis")))
(out / "big-over.pdf").write_bytes(pdf(lines_of(8_000_000, "overfixture", 1)))
(out / "big-under.pdf").write_bytes(pdf(lines_of(5_000_000, "underfixture", 2)))
