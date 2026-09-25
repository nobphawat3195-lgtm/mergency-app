# เว็บแอปลูกค้า (FixGo) และแอปช่าง (FixGo Fixer) + Caddy ในอิมเมจเดียว
# build จาก root ของ repo: docker compose ส่ง API_BASE_URL มาเป็น build arg

FROM ghcr.io/cirruslabs/flutter:3.35.4 AS build
ARG API_BASE_URL
RUN test -n "$API_BASE_URL" || (echo "ต้องส่ง API_BASE_URL" && exit 1)
WORKDIR /src
COPY packages ./packages
COPY apps/customer ./apps/customer
COPY apps/provider ./apps/provider
RUN for app in customer provider; do \
      cd /src/apps/$app \
      && flutter pub get \
      && flutter build web --release --no-web-resources-cdn \
           --dart-define=API_BASE_URL=$API_BASE_URL \
      || exit 1; \
    done

FROM caddy:2-alpine
COPY --from=build /src/apps/customer/build/web /srv/web
COPY --from=build /src/apps/provider/build/web /srv/fixer
