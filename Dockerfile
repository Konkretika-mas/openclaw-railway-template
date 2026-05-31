# Используем твой базовый образ
FROM node:24-bookworm

# Устанавливаем системные зависимости:
# - Общие для OpenClaw и твоей предыдущей настройки (git, gosu, procps, tini, build-essential, zip, unzip)
# - Python и pip для Playwright
# - Специальные библиотеки для работы Playwright с браузерами (chromium)
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
    # Дополнительные зависимости для Playwright Chromium
    fonts-liberation \
    libsecret-1-0 \
    libgbm-dev \
 && rm -rf /var/lib/apt/lists/*

# Устанавливаем OpenClaw и ClawHub глобально
RUN npm install -g openclaw@latest --unsafe-perm && npm cache clean --force
RUN npm install -g clawhub@latest

# Создаем рабочую директорию
WORKDIR /app

# Копируем файлы твоего проекта и устанавливаем зависимости pnpm (если они есть)
# Это сохраняет твой предыдущий подход к управлению зависимостями Node.js
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN corepack enable && pnpm install --frozen-lockfile --prod

# Копируем исходники и скрипт entrypoint
COPY src ./src
COPY --chmod=755 entrypoint.sh ./entrypoint.sh

# Создаем пользователя openclaw и настраиваем права
RUN useradd -m -s /bin/bash openclaw \
 && chown -R openclaw:openclaw /app \
 && mkdir -p /data && chown openclaw:openclaw /data \
 && mkdir -p /home/linuxbrew/.linuxbrew && chown -R openclaw:openclaw /home/linuxbrew

# Переключаемся на пользователя openclaw для установки Homebrew и Playwright
USER openclaw

# Устанавливаем Homebrew (как в твоем предыдущем Dockerfile)
RUN NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Устанавливаем Python Playwright и браузер Chromium под пользователем openclaw
# Playwright версии 1.44.0, которая была в моем изначальном скрипте
# Используем виртуальное окружение, т.к. Debian Bookworm блокирует системный pip (PEP 668)
RUN python3 -m venv /home/openclaw/playwright-venv \
 && /home/openclaw/playwright-venv/bin/pip install --no-cache-dir playwright==1.44.0 \
 && /home/openclaw/playwright-venv/bin/python -m playwright install chromium

# Настраиваем переменные окружения, включая те, что связаны с Homebrew и портом
ENV PATH="/home/openclaw/playwright-venv/bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"
ENV HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"
ENV HOMEBREW_CELLAR="/home/linuxbrew/.linuxbrew/Cellar"
ENV HOMEBREW_REPOSITORY="/home/linuxbrew/.linuxbrew/Homebrew"

ENV PORT=8080
ENV OPENCLAW_ENTRY=/usr/local/lib/node_modules/openclaw/dist/entry.js
EXPOSE 8080

# Настраиваем Healthcheck, как в твоем предыдущем Dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
 CMD curl -f http://localhost:8080/setup/healthz || exit 1

# Возвращаемся к root для entrypoint
USER root
ENTRYPOINT ["tini", "--", "./entrypoint.sh"]
