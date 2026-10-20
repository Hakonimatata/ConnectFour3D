# Bygger både spillserveren og web-klienten fra kildekoden.
#   DOMAIN=spill.example.no docker compose -f deploy/docker-compose.yml up -d --build
# Første bygg laster ned Godot (~50 MB) og eksportmalene (~1,3 GB). Senere bygg bruker cache.

ARG GODOT_VERSION=4.7

# ---- Godot (headless) -------------------------------------------------------
FROM debian:bookworm-slim AS godot
ARG GODOT_VERSION
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates wget unzip libfontconfig1 \
	&& rm -rf /var/lib/apt/lists/*
RUN wget -q https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip \
	&& unzip -q Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip \
	&& mv Godot_v${GODOT_VERSION}-stable_linux.x86_64 /usr/local/bin/godot \
	&& rm Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip

# ---- Eksportmaler for web (eget lag, så de caches) ---------------------------
FROM godot AS templates
ARG GODOT_VERSION
RUN wget -q https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_export_templates.tpz \
	&& mkdir -p /root/.local/share/godot/export_templates/${GODOT_VERSION}.stable \
	&& unzip -q -j Godot_v${GODOT_VERSION}-stable_export_templates.tpz "templates/web_nothreads_*" "templates/version.txt" \
		-d /root/.local/share/godot/export_templates/${GODOT_VERSION}.stable \
	&& rm Godot_v${GODOT_VERSION}-stable_export_templates.tpz

# ---- Spillserveren ----------------------------------------------------------
FROM godot AS server
WORKDIR /app
COPY . .
RUN godot --headless --path /app --import || true
ENV PORT=8080
EXPOSE 8080
CMD ["godot", "--headless", "--path", "/app", "--", "--server"]

# ---- Web-klienten (eksport) -------------------------------------------------
FROM templates AS web-build
WORKDIR /app
COPY . .
RUN godot --headless --path /app --import || true
RUN mkdir -p /out/web && godot --headless --path /app --export-release "Web" /out/web/index.html

# ---- Caddy: serverer web-klienten og sender /ws videre til spillserveren ----
FROM caddy:2 AS web
COPY deploy/Caddyfile /etc/caddy/Caddyfile
COPY --from=web-build /out/web /srv/web
