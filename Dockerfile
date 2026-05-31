FROM node:24-bookworm

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    gosu \
    procps \
    python3 python3-pip python3-venv \
    tini \
    build-essential \
    zip \
    unzip \
    fonts-liberation \
    libsecret-1-0 \
    libgbm-dev \
 && rm -rf /var/lib/apt/lists/*

RUN npm install -g openclaw@latest --unsafe-perm && npm cache clean --force
RUN npm install -g clawhub@latest

WORKDIR /app

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN corepack enable && pnpm install --frozen-lockfile --prod

COPY src ./src
COPY --chmod=755 entrypoint.sh ./entrypoint.sh

RUN useradd -m -s /bin/bash openclaw \
 && chown -R openclaw:openclaw /app \
 && mkdir -p /data && chown openclaw:openclaw /data \
 && mkdir -p /home/linuxbrew/.linuxbrew && chown -R openclaw:openclaw /home/linuxbrew

USER openclaw

# Устанавливаем Homebrew
RUN NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# --- ВОТ ИЗМЕНЕНИЕ ---
# Это "сломает" кэш для следующих слоев и принудит переустановить Playwright
RUN echo "TRIGGER PLAYWRIGHT REINSTALL: $(date)"

# Создаем виртуальную среду для Playwright
ENV PLAYWRIGHT_VENV=/home/openclaw/venv
RUN python3 -m venv $PLAYWRIGHT_VENV

# Настраиваем PATH, чтобы python и pip из venv использовались по умолчанию
ENV PATH="$PLAYWRIGHT_VENV/bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"

# Устанавливаем Playwright и его браузеры ВНУТРИ виртуальной среды
RUN $PLAYWRIGHT_VENV/bin/pip install --no-cache-dir playwright==1.44.0 \
 && python3 -m playwright install chromium

# Переменные окружения Homebrew (повторно устанавливаем, чтобы убедиться в порядке)
ENV HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"
ENV HOMEBREW_CELLAR="/home/linuxbrew/.linuxbrew/Cellar"
ENV HOMEBREW_REPOSITORY="/home/linuxbrew/.linuxbrew/Homebrew"

ENV PORT=8080
ENV OPENCLAW_ENTRY=/usr/local/lib/node_modules/openclaw/dist/entry.js
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
 CMD curl -f http://localhost:8080/setup/healthz || exit 1

USER root
ENTRYPOINT ["tini", "--", "./entrypoint.sh"]
