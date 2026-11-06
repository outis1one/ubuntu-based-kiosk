# Koha (open-source library system) built from the Koha project's own Debian
# packages - no third-party Koha images involved.
#
#   KOHA_SUITE         stable (default) | oldstable | unstable
#   KEEP_TRANSLATIONS  no (default) trims ~650 MB of non-English .po files;
#                      set "yes" if you want to install other languages later
FROM debian:bookworm-slim

ARG KOHA_SUITE=stable
ARG KEEP_TRANSLATIONS=no
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gnupg tzdata

# Optional: drop extra CA certificates (*.crt) into ./certs/ before building if
# you are behind a TLS-inspecting proxy. Empty by default.
COPY certs/ /usr/local/share/ca-certificates/extra/
RUN update-ca-certificates

RUN curl -fsSL https://debian.koha-community.org/koha/gpg.asc | gpg --dearmor -o /usr/share/keyrings/koha.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/koha.gpg] https://debian.koha-community.org/koha ${KOHA_SUITE} main bookworm" \
      > /etc/apt/sources.list.d/koha.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends koha-common mariadb-client \
 && a2enmod rewrite headers proxy_http cgi deflate >/dev/null \
 && a2dissite 000-default >/dev/null 2>&1 || true \
 && if [ "$KEEP_TRANSLATIONS" != "yes" ]; then rm -rf /usr/share/koha/misc/translator/po; fi \
 && rm -rf /var/lib/apt/lists/* /usr/share/doc/*

COPY bootstrap.pl entrypoint.sh /opt/koha-init/
COPY seed/ /opt/koha-init/seed/
RUN chmod 0755 /opt/koha-init/entrypoint.sh && chmod -R a+rX /opt/koha-init

EXPOSE 80 8081
VOLUME ["/var/lib/koha"]
HEALTHCHECK --interval=30s --timeout=10s --start-period=300s --retries=5 \
  CMD curl -fsS -o /dev/null http://127.0.0.1:80/ && curl -fsS -o /dev/null http://127.0.0.1:8081/ || exit 1
ENTRYPOINT ["/opt/koha-init/entrypoint.sh"]
