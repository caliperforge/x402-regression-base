# base-x402-ci runner image.
#
# Pinned Foundry image so a `uses: caliperforge/x402-regression-base@v0.1.0`
# reference gets a byte-identical harness every run. The harness code
# (run.sh, ci/live_*.sh, script/, test/, src/, foundry.toml) is baked into
# the image at build time; the adopter's own repo is not copied in.
#
# Runtime working directory: /github/workspace (GH Actions mounts the
# adopter checkout there). Report JSON lands there so upload-artifact can
# grab it. Harness source stays at /action.
#
# No secrets are ever COPY'd into the image. The .dockerignore in this
# repo blacklists .env*, broadcast/, cache/, out/ to eliminate accidental
# key exposure via image layers.

FROM ghcr.io/foundry-rs/foundry:v1.0.0

# apt on the foundry-rs Debian base (foundry:v1.0.0 ships Debian, not Alpine).
# bash + jq + curl are load-bearing for entrypoint.sh and ci/live_*.sh. git
# required for `forge install` and submodule resolution. coreutils/util-linux/
# findutils give GNU timeout/flock/find parity with the CI runners.
USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends bash git jq curl coreutils util-linux findutils && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /action

# Copy the pinned harness. .dockerignore filters out cache/, out/,
# broadcast/, .env*, node_modules/, .git/ to keep the image tight and
# key-adjacent artifacts out of layers.
COPY . /action

# Foundry deps. --no-git avoids pinning to a moving HEAD; the lib/ tree
# already carries the pinned submodule commit for reproducibility.
RUN if [ -d lib ] && [ -z "$(ls -A lib 2>/dev/null)" ]; then \
        forge install --no-git foundry-rs/forge-std; \
    fi

# Prebuild once at image bake so `forge test` at runtime hits a warm cache.
RUN forge build --sizes || true

RUN chmod +x /action/entrypoint.sh /action/run.sh /action/ci/*.sh

ENTRYPOINT ["/action/entrypoint.sh"]
