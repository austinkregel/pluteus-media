# Committed fixtures

Every other fixture the suite uses is built at test time — `media!/2` makes real media
with ffmpeg, and `:zip.create/3` makes a ZIP. What is here could not be.

## `comic.cbr`

A three-page comic archive in RAR 5.0, 3275 bytes, stored rather than compressed.

| | |
| --- | --- |
| sha256 | `1820bfe83320e63e30c6da4b4779aa2928a2f42620fbe42cccfdf1f8f965d439` |
| identifies as | `fmt/613`, RAR Archive 5.0, `application/vnd.rar` |
| holds | `page-001.png`, `page-002.png`, `page-003.png` — 120×160 ffmpeg test patterns |

**Why it is committed rather than generated.** Nothing in Debian main writes RAR. The
unRAR licence permits reading and restricts building a compressor, so `libarchive` reads
this format and cannot produce it, `7z` cannot produce it, and the only writer is RARLAB's
own `rar` from `non-free`. Installing a non-free packer into the image to build a test
input would be a dependency the deployment does not otherwise have.

**Why it is stored and not compressed.** `libarchive` does two separable jobs on a RAR:
parse the container, and decompress the entries. A stored archive exercises only the first,
so the comic path's tests do not rest on the RAR decompressor. This is also what real comic
archives look like — a 52 MB `.cbr` of 80 JPEGs measured 98.8% of its entries' total size,
because JPEG does not compress further.

**How it was made.** In a throwaway container with `rar` installed from `bookworm/non-free`,
never into the image:

```
for n in 001 002 003; do
  ffmpeg -loglevel error -f lavfi -i "testsrc=size=120x160:duration=1:rate=1" \
    -frames:v 1 "page-$n.png"
done
rar a -m0 comic.cbr page-001.png page-002.png page-003.png
```

It identifies byte-for-byte as the household's own comics do, down to Siegfried's
`extension mismatch` warning, so a test passing against it is a test passing against the
real shape.
