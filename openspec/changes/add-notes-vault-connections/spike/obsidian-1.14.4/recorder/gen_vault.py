#!/usr/bin/env python3
"""Generate the D8 fixture vault for spikes 3.5 and 3.6.

Every non-ASCII file name that must be NFD is built with combining marks
(U+0301, U+0308) so that the bytes on disk are decomposed.
"""
import base64
import json
import os
import sys
import unicodedata

VAULT = sys.argv[1]

ACUTE = "́"
DIAER = "̈"
CAFE_NFD = "Cafe" + ACUTE            # Café, decomposed
CAFE_NFC = "Café"               # Café, precomposed
RESUME_NFD = "Re" + ACUTE + "sume" + ACUTE
RESUME_NFC = "Résumé"
NAIVE_NFC = "Naïve"
NAIVE_NFD = "Nai" + DIAER + "ve"

FENCE = "```"

files = {}

files["Home.md"] = f"""---
aliases: [Start, Main Page]
tags: [fm-tag, nested/fm-child]
---
# Home

Links to [[Alpha]], [[Projects/Alpha|Project Alpha]], [[Archive/2024/Alpha]] and [[2024/Alpha]].
Heading link [[Beta#Section One]] and nested heading [[Beta#Section One#Subsection]].
Block link [[Beta#^block1]].
Aliased [[Gamma|the third letter]].
Alias as target [[G]] and [[Gamma Ray]] (aliases of Gamma; they must not resolve).
Missing [[Missing Note]] and missing with heading [[Missing Note#Part]].
Case mismatch [[beta]] and with extension [[Beta.md]].
NFC-written link to the NFD file [[{CAFE_NFC}]] and NFD-written link [[{CAFE_NFD}]].
NFC-written link [[{RESUME_NFC}]] to the NFD file in Notes.
Spaces [[Note with spaces]].
Image as a link, not an embed: [[photo.png]].
Partial path [[Sub/Delta]].

Embeds:
![[Beta]]
![[Beta#Section Two]]
![[Beta#^block2]]
![[images/diagram.png]]
![[photo.png|200]]
![[spec.pdf]]
![[Missing Image.png]]

%% A comment with [[Commented Link]] and #comment-tag %%

%%
Multi-line comment
[[Commented Multi]] #comment-multi-tag
%%

Inline code `[[InlineCode]]` and `#inline-code-tag`.

{FENCE}
[[InFence]] #fence-tag
{FENCE}

~~~md
![[InTildeFence]]
~~~

Inline tags: #home #nested/child #CamelTag #with-dash #with_underscore #123 #1a
Not tags: email@example.com#notatag, url https://example.com/#anchor, &#35;escaped.
"""

files["Alpha.md"] = """# Alpha (root)

Links to [[Projects/Alpha]] and [[Archive/2024/Alpha|the archived one]].
"""

files["Projects/Alpha.md"] = """# Alpha (Projects)

Link [[Alpha]] from inside Projects. Link [[Beta]].
"""

files["Archive/2024/Alpha.md"] = """# Alpha (Archive 2024)

Link [[Alpha]] from inside Archive/2024.
"""

files["Beta.md"] = """---
tags: beta-tag
---
# Beta

Intro paragraph. ^intro

## Section One

### Subsection

Paragraph with a block id. ^block1

## Section Two

- list item one ^block2
- list item two

> quote block

^quoteblock

| a | b |
|---|---|
| 1 | 2 |

^tableblock

## Section with [[Alpha]] link in heading

## Duplicate

## Duplicate
"""

files["Gamma.md"] = """---
aliases:
  - G
  - Gamma Ray
tags:
  - greek
  - "#hash-in-fm"
---
# Gamma

See [[Beta]].
"""

files[CAFE_NFD + ".md"] = f"""# {CAFE_NFC}

The file name is NFD. Back to [[Home]]. Tag written NFD: #cafe{ACUTE} and NFC: #{CAFE_NFC.lower()}.
"""

files["Notes/" + RESUME_NFD + ".md"] = f"""# {RESUME_NFC}

NFD-written link [[{NAIVE_NFD}]] to the NFC-named file. NFC link [[{NAIVE_NFC}]].
"""

files["Notes/" + NAIVE_NFC + ".md"] = """# Naive

The file name is NFC.
"""

files["Ideas/Delta.md"] = "# Delta (Ideas)\n"
files["Work/Sub/Delta.md"] = "# Delta (Work/Sub)\n"

files["Root Ref.md"] = """# Root Ref

[[Delta]] [[Alpha]] [[2024/Alpha]] [[Projects/Alpha]] [[Sub/Delta]] [[Ideas/Delta]]
"""

files["Ideas/Ref Ideas.md"] = """# Ref Ideas

[[Delta]] [[Alpha]]
"""

files["Work/Sub/Ref Work.md"] = """# Ref Work

[[Delta]] [[Alpha]]
"""

files["Tags.md"] = """---
tags: [fm-one, fm-two, Fm-One]
tag: singular-key
Tags: capital-key
---
# Tags

#inline #inline/child #UPPER #upper #tag/with/deep/nesting #日本語
Tag at end of sentence #end.
Trailing slash #trail/ and #a/b/
## Heading #heading-tag
- [ ] task #task-tag
"""

files["FmTags String.md"] = """---
tags: "alpha-str, beta-str"
---
Comma string in tags.
"""

files["Code.md"] = f"""# Code

    [[IndentedCode]] #indented-tag

``[[DoubleTick]]`` and `![[InlineEmbed]]`

{FENCE}js
const s = "[[InJsFence]]"; // #js-tag
{FENCE}

<!-- [[HtmlComment]] #html-comment-tag -->

$$
[[InMath]]
$$

Real link after code: [[Beta]].
"""

files["Callouts.md"] = """# Callouts

> [!note] Title with [[Alpha]]
> Body with [[Beta#Section One]] and #callout-tag
> ![[photo.png]]

> [!tip]- Folded
> [[Gamma]]
"""

files["Frontmatter.md"] = """---
title: Frontmatter test
related: "[[Gamma]]"
links:
  - "[[Beta]]"
  - "[[Missing FM]]"
  - "[[Projects/Alpha|PA]]"
count: 42
done: true
date: 2024-01-01
cssclasses: [wide]
---
Body [[Alpha]].
"""

files["Docs/Markdown Links.md"] = """# Markdown links

[md link](../Beta.md)
[md link no ext](../Beta)
[encoded](../Note%20with%20spaces.md)
[angle](<../Note with spaces.md>)
[heading](../Beta.md#Section%20One)
[same folder](Sibling.md)
[vault absolute](/Beta.md)
[external](https://example.com)
![md image](../images/diagram.png)
[[Projects/Alpha.md]]
"""

files["Docs/Sibling.md"] = "# Sibling\n\n[[Markdown Links]]\n"

files["Self Links.md"] = """# Top

[[#Top]] [[#^selfblock]] [[Self Links#Top]]

Paragraph ^selfblock
"""

files["Daily/2024-01-01.md"] = "# 2024-01-01\n\n[[Home]] #daily\n"
files["Note with spaces.md"] = "# Note with spaces\n\nBody.\n"
files["Epsilon.md"] = "# Epsilon (root)\n"

# --- Rename fixtures (OBS-024 goldens) ---
files["RenameTargets/Shortest.md"] = "# Shortest\n\n## Part\n\nText ^sblk\n"
files["RenameTargets/Aliased.md"] = "# Aliased\n"
files["RenameTargets/Headed.md"] = "# Headed\n\n## Section A\n\nText ^blk\n"
files["RenameTargets/Embedded.md"] = "# Embedded\n\n## Part\n\nText ^emb\n"
files["RenameTargets/Collide.md"] = "# Collide\n"

files["RenameSources/Uses Shortest.md"] = """[[Shortest]]
[md](../RenameTargets/Shortest.md)
"""
files["RenameSources/Uses Aliased.md"] = """[[Aliased|Display Text]]
[[RenameTargets/Aliased|Path Alias]]
[Md Alias](../RenameTargets/Aliased.md)
"""
files["RenameSources/Uses Headed.md"] = """[[Headed#Section A]]
[[Headed#Section A|alias]]
[[Headed#^blk]]
[md](../RenameTargets/Headed.md#Section%20A)
"""
files["RenameSources/Uses Embedded.md"] = """![[Embedded]]
![[Embedded#Part]]
![[Embedded#^emb]]
![md](../RenameTargets/Embedded.md)
"""
files["RenameSources/Uses Collide.md"] = "[[Collide]]\n[[Collide|aliased]]\n"

# --- Event fixtures (spike 3.5) ---
files["Events/Folder3/One.md"] = "# One\n\n[[Two]]\n"
files["Events/Folder3/Two.md"] = "# Two\n\n[[Three]]\n"
files["Events/Folder3/Three.md"] = "# Three\n"
files["Events/Linker.md"] = "[[Events/Folder3/One]] [[Two]] [[Three|t]]\n"
files["Events/to-delete.md"] = "delete me\n"
files["Events/to-trash.md"] = "trash me\n"
files["Events/external.md"] = "external target\n"
files["Events/Sub/keep.md"] = "keep\n"
files["Events/ExtFolder/x.md"] = "x\n"
files["Events/ExtFolder/y.md"] = "[[x]]\n"

PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
)
PDF = b"%PDF-1.1\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n"

for rel, body in files.items():
    path = os.path.join(VAULT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(body)

for rel, data in {"images/diagram.png": PNG, "photo.png": PNG, "attachments/spec.pdf": PDF}.items():
    path = os.path.join(VAULT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)

# Obsidian config for the test vault.
obs = os.path.join(VAULT, ".obsidian")
plugin_dir = os.path.join(obs, "plugins", "ratatoskr-spike")
os.makedirs(plugin_dir, exist_ok=True)
with open(os.path.join(obs, "community-plugins.json"), "w") as f:
    json.dump(["ratatoskr-spike"], f)
with open(os.path.join(obs, "app.json"), "w") as f:
    json.dump({"alwaysUpdateLinks": True}, f)

md = [k for k in files]
print(f"wrote {len(md)} markdown files and 3 attachments")
for k in md:
    if k != unicodedata.normalize("NFC", k):
        print("NFD name:", k.encode("unicode_escape").decode())
