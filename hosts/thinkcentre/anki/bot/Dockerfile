# anki-bot — small HTTP service that adds cards to per-user Anki collections
# and syncs them to ankiweb.net. Replaces the headless-Anki-desktop +
# AnkiConnect approach with a thin Python wrapper around the `anki` package.

FROM python:3.12-slim

# Anki's collection engine has a few native deps for sqlite + media handling.
RUN apt-get update && apt-get install --no-install-recommends -y \
        curl ca-certificates libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:${PATH}"

WORKDIR /app
COPY pyproject.toml /app/
RUN uv pip install --system --no-cache \
        "anki==25.9.2" \
        "fastapi>=0.118" \
        "uvicorn[standard]>=0.30" \
        "pydantic>=2.0"

COPY main.py /app/
COPY curricula /app/curricula

RUN useradd -m -u 1000 anki && mkdir -p /data && chown -R anki /data /app
USER anki

ENV ANKI_DATA_DIR=/data
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD curl -fsS http://127.0.0.1:8080/health || exit 1

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080", "--log-level", "info"]
