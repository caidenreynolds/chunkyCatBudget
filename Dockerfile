FROM ghcr.io/cirruslabs/flutter:stable AS frontend-builder

ARG GIT_COMMIT=unknown
ARG BUILD_TIME=unknown
ARG BUILD_NUMBER=

WORKDIR /app

COPY pubspec.yaml pubspec.lock /app/
RUN flutter pub get

COPY lib /app/lib
COPY web /app/web
RUN flutter build web --release \
    && APP_VERSION="$(awk -F': ' '/^version:/ {print $2}' pubspec.yaml)" \
    && VERSION="${APP_VERSION%%+*}" \
    && PUBSPEC_BUILD_NUMBER="${APP_VERSION#*+}" \
    && if [ "$PUBSPEC_BUILD_NUMBER" = "$APP_VERSION" ]; then PUBSPEC_BUILD_NUMBER=""; fi \
    && EFFECTIVE_BUILD_NUMBER="${BUILD_NUMBER:-$PUBSPEC_BUILD_NUMBER}" \
    && printf '{\n  "version": "%s",\n  "buildNumber": "%s",\n  "commit": "%s",\n  "buildTime": "%s"\n}\n' \
        "$VERSION" "$EFFECTIVE_BUILD_NUMBER" "$GIT_COMMIT" "$BUILD_TIME" > /app/build/web/version.json

FROM python:3.12-slim AS app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DATABASE_URL=sqlite:////data/budget.db \
    CORS_ORIGINS=*

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends nginx supervisor \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default \
    && mkdir -p /data /run/nginx /var/log/nginx

COPY backend/requirements.txt /app/backend/requirements.txt
RUN pip install --no-cache-dir -r /app/backend/requirements.txt

COPY backend /app/backend
COPY --from=frontend-builder /app/build/web /usr/share/nginx/html
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

VOLUME ["/data"]
EXPOSE 80

CMD ["supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
