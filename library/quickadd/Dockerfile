# Quick Add: scan an ISBN, the book is in the catalogue. Standard-library Python
# plus yaz (the Z39.50 client). Same Debian base as the Koha image, so it adds
# one small layer instead of another base-image pull.
FROM debian:bookworm-slim
ENV DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates python3 yaz tzdata \
 && rm -rf /var/lib/apt/lists/*

# Optional: drop extra CA certificates (*.crt) into ./certs/ before building if
# you are behind a TLS-inspecting proxy. Empty by default.
COPY certs/ /usr/local/share/ca-certificates/extra/
RUN update-ca-certificates

RUN useradd --system --uid 10001 --home-dir /app quickadd \
 && mkdir -p /app /data && chown quickadd /data
COPY app.py index.html /app/
USER quickadd
WORKDIR /app

EXPOSE 8082
VOLUME ["/data"]
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD python3 -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8082/healthz', timeout=3).status==200 else 1)"
CMD ["python3", "/app/app.py"]
