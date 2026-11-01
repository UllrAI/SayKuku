FROM nginx/nginx-unprivileged:stable-alpine-slim

ARG SOURCE_COMMIT=unknown

LABEL org.opencontainers.image.source="https://github.com/UllrAI/SayKuku" \
      org.opencontainers.image.title="SayKuku website" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.revision=$SOURCE_COMMIT

USER root
COPY --chown=101:101 nginx.conf /etc/nginx/conf.d/default.conf
COPY dist/ /usr/share/nginx/html/
RUN printf '%s\n' "$SOURCE_COMMIT" > /usr/share/nginx/html/revision.txt
USER 101

EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1
