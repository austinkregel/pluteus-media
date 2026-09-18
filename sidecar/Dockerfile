FROM python:3.12-slim

# ffmpeg decodes the requested stream and extent; fpcalc computes the
# Chromaprint acoustic fingerprint.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg libchromaprint-tools \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /sidecar
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# numba caches compiled functions beside the code unless told otherwise, and
# the container's filesystem is read-only; /tmp is its one writable place.
ENV NUMBA_CACHE_DIR=/tmp/numba

EXPOSE 8000
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
