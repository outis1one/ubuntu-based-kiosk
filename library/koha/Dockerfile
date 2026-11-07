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

# Each step stands alone and fails the build on error: a swallowed failure here once produced a
# "successful" image with no Koha in it. memcached and cron are named explicitly rather than
# trusted to arrive as dependencies of koha-common.
RUN curl -fsSL https://debian.koha-community.org/koha/gpg.asc | gpg --dearmor -o /usr/share/keyrings/koha.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/koha.gpg] https://debian.koha-community.org/koha ${KOHA_SUITE} main bookworm" \
      > /etc/apt/sources.list.d/koha.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends koha-common mariadb-client memcached cron

RUN a2enmod rewrite headers proxy_http cgi deflate >/dev/null \
 && (a2dissite 000-default >/dev/null 2>&1 || true)

RUN if [ "$KEEP_TRANSLATIONS" != "yes" ]; then rm -rf /usr/share/koha/misc/translator/po; fi \
 && rm -rf /var/lib/apt/lists/* /usr/share/doc/*

# Refuse to produce an image that cannot run.
RUN for c in koha-create koha-plack koha-zebra koha-rebuild-zebra koha-upgrade-schema apache2ctl memcached cron mariadb zebrasrv; do \
      command -v "$c" >/dev/null || { echo "BUILD ERROR: $c is missing from the image" >&2; exit 1; }; \
    done

# The endpoint Quick Add uses to recognise a signed-in staff user (see the file header).
COPY quickadd-session.pl /usr/share/koha/intranet/cgi-bin/svc/quickadd-session
# (the return script lives beside the staff .pl scripts, not under svc/: Koha's svc Plack app 500s on it)
COPY quickadd-return.pl quickadd-value.pl /usr/share/koha/intranet/cgi-bin/
RUN chmod 0755 /usr/share/koha/intranet/cgi-bin/svc/quickadd-session /usr/share/koha/intranet/cgi-bin/quickadd-return.pl /usr/share/koha/intranet/cgi-bin/quickadd-value.pl

COPY bootstrap.pl ensure.pl entrypoint.sh /opt/koha-init/
COPY seed/ /opt/koha-init/seed/
RUN chmod 0755 /opt/koha-init/entrypoint.sh && chmod -R a+rX /opt/koha-init

EXPOSE 80 8081
VOLUME ["/var/lib/koha"]
HEALTHCHECK --interval=10s --timeout=10s --start-period=300s --retries=6 \
  CMD test -f /run/koha-ready && curl -fsS -o /dev/null http://127.0.0.1:80/ && curl -fsS -o /dev/null http://127.0.0.1:8081/ || exit 1
ENTRYPOINT ["/opt/koha-init/entrypoint.sh"]
