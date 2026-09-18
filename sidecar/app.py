"""The analysing sidecar (spec-04 §8.2, §8.3).

It measures what the deployment's native tools cannot: constant-Q chroma and
the key and mode estimated from it, beat and onset tracking, and an acoustic
fingerprint. It meets the same contract as every tool: it describes itself
without analysing anything, analyses one input per request, returns
measurements by name as it computed them, and writes nothing. It holds no
database credentials, reads storage through a read-only mount, and refuses a
path outside the roots it is given.

A request the sidecar can never satisfy — a path outside its roots, bytes that
do not decode — is answered 422, which the deployment records as a permanent
failure. Anything else that goes wrong is answered 500, which it retries.
"""

import json
import os
import subprocess
import tempfile

import librosa
import numpy as np
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

NAME = "pluteus-sidecar"
VERSION = f"1+librosa{librosa.__version__}"
SCHEMA_VERSION = 1
SAMPLE_RATE = 22_050
PITCH_CLASSES = ["c", "c_sharp", "d", "d_sharp", "e", "f", "f_sharp", "g", "g_sharp", "a", "a_sharp", "b"]

# Krumhansl and Kessler's key profiles, from C.
MAJOR = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88])
MINOR = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17])

ROOTS = [os.path.realpath(root) for root in os.environ["ALLOWED_ROOTS"].split(":") if root]

app = FastAPI()


class Request(BaseModel):
    path: str
    stream_index: int | None = None
    start_ms: int | None = None
    end_ms: int | None = None


@app.get("/describe")
def describe():
    return {"name": NAME, "version": VERSION, "schema_version": SCHEMA_VERSION}


@app.post("/analyse")
def analyse(request: Request):
    path = os.path.realpath(request.path)

    if not any(os.path.commonpath([path, root]) == root for root in ROOTS):
        raise HTTPException(status_code=422, detail={"refused": "path outside the storage roots"})

    samples = decode(path, request)

    if samples.size == 0:
        raise HTTPException(status_code=422, detail={"undecodable": "no samples decoded"})

    measurements = {}
    measurements.update(chroma_and_key(samples))
    measurements.update(rhythm(samples))
    measurements.update(fingerprint(samples))

    return {"schema_version": SCHEMA_VERSION, "measurements": measurements}


def decode(path, request):
    args = ["ffmpeg", "-loglevel", "error", "-nostdin"]

    if request.start_ms is not None:
        args += ["-ss", f"{request.start_ms / 1000:.3f}", "-to", f"{request.end_ms / 1000:.3f}"]

    stream = "0:a:0" if request.stream_index is None else f"0:{request.stream_index}"
    args += ["-i", path, "-map", stream, "-ac", "1", "-ar", str(SAMPLE_RATE), "-f", "f32le", "-"]

    result = subprocess.run(args, capture_output=True)

    if result.returncode != 0:
        raise HTTPException(status_code=422, detail={"undecodable": result.stderr.decode(errors="replace")})

    return np.frombuffer(result.stdout, dtype="<f4").astype(np.float32)


def chroma_and_key(samples):
    chroma = librosa.feature.chroma_cqt(y=samples, sr=SAMPLE_RATE).mean(axis=1)
    measurements = {f"cqt_chroma_{pitch}": float(value) for pitch, value in zip(PITCH_CLASSES, chroma)}

    scores = [
        (float(np.corrcoef(np.roll(profile, tonic), chroma)[0, 1]), tonic, major)
        for tonic in range(12)
        for profile, major in ((MAJOR, 1), (MINOR, 0))
    ]
    correlation, tonic, major = max(scores)

    measurements["key_pitch_class"] = tonic
    measurements["key_mode_major"] = major
    measurements["key_correlation"] = correlation
    return measurements


def rhythm(samples):
    tempo, beats = librosa.beat.beat_track(y=samples, sr=SAMPLE_RATE)
    onsets = librosa.onset.onset_detect(y=samples, sr=SAMPLE_RATE)
    duration = samples.size / SAMPLE_RATE

    return {
        "tempo_bpm": float(np.atleast_1d(tempo)[0]),
        "beat_count": int(len(beats)),
        "onset_rate_hz": float(len(onsets) / duration),
    }


def fingerprint(samples):
    with tempfile.NamedTemporaryFile(suffix=".wav", dir="/tmp") as wav:
        pcm = (np.clip(samples, -1.0, 1.0) * 32767).astype("<i2").tobytes()
        encode = subprocess.run(
            ["ffmpeg", "-loglevel", "error", "-nostdin", "-y", "-f", "s16le", "-ar", str(SAMPLE_RATE), "-ac", "1",
             "-i", "-", wav.name],
            input=pcm,
            capture_output=True,
        )

        if encode.returncode != 0:
            raise RuntimeError(encode.stderr.decode(errors="replace"))

        result = subprocess.run(["fpcalc", "-json", wav.name], capture_output=True, check=True)

    computed = json.loads(result.stdout)
    return {"acoustic_fingerprint": computed["fingerprint"], "fingerprint_duration_s": float(computed["duration"])}
