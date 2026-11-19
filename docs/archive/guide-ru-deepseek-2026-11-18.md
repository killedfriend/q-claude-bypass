# Claude Code и Claude Desktop на DeepSeek API

Полная инструкция: от терминального Claude Code до настоящего Claude Desktop,
включая MITM-перехват. Windows / macOS / Linux.

Дата: 2026-11-18. Проверено на Claude Code 2.1.326 и Claude Desktop 5.11492.5
(MSIX, Windows 11). DeepSeek: `deepseek-flash` (V4.1-Flash-1017) и `deepseek-v4-pro`.

> Как читать этот документ агенту: идите по частям сверху вниз, после каждого
> шага выполняйте проверку. Части A и B работают на всех ОС. Часть C (десктоп) —
> только Windows и macOS; официального Claude Desktop для Linux нет.
> Если проверка не совпала с ожидаемой — смотрите раздел 7, не продолжайте.

---

## 0. TL;DR

| Задача | Что нужно | Время |
|---|---|---|
| Claude Code на DeepSeek | 8 переменных окружения | 15 мин |
| + логи, роутинг, учёт денег | локальный шлюз (Node 22) | 30 мин |
| Claude Desktop на DeepSeek | hosts + локальный CA + TLS на 443 | 1–2 часа |

Главное: **Claude Code не нужно патчить**. DeepSeek отдаёт Anthropic-совместимый
API, и клиент просто перенаправляется переменной `ANTHROPIC_BASE_URL`.
Claude Desktop так не умеет — его приходится перехватывать на уровне TLS.

---

## 1. Теория, без которой не получится

### 1.1 Почему это вообще работает

Claude Code — обычный HTTP-клиент к Anthropic Messages API. Модель определяется
не клиентом, а адресом, на который он шлёт `POST /v1/messages`. DeepSeek держит
совместимый эндпоинт:

```
https://api.deepseek.com/anthropic
```

Он принимает тот же формат: `system`, `messages`, `tools`, `tool_choice`,
`thinking`, `output_config.effort`, `stream`. Отдаёт те же блоки `text`,
`tool_use`, `thinking` и те же SSE-события. Поэтому агентный цикл, тулы,
permissions, hooks, skills и субагенты работают без единой правки кода.

Claude Desktop устроен иначе: адрес API и способ авторизации зашиты, а вход
идёт через сервер Anthropic. Поэтому его приходится обманывать (часть C).

### 1.2 Семь ловушек, которые ловятся только опытом

1. **Base URL обязан быть со схемой.** `api.deepseek.com/anthropic` из
   документации DeepSeek даёт `API Error: Invalid URL`. Нужен
   `https://api.deepseek.com/anthropic`.
2. **Имя модели обязано начинаться с `claude`.** Claude Code валидирует его на
   клиенте и на `deepseek-flash` отвечает
   `[claude-code:unrecognized_model]` **до** запроса к API. DeepSeek на своей
   стороне мапит: `claude-opus*` → `deepseek-v4-pro`, любой другой `claude*` →
   `deepseek-flash`. Суффикс `[1m]` включает контекст 1M.
3. **Документы нельзя отправлять инлайном.** `document` с `source.type: base64`
   даёт 400: DeepSeek принимает только `source.type: text` и `file` (через
   Files API). Хуже: `document` внутри `tool_result` **молча игнорируется** —
   модель отвечает `NO-DOCUMENT`. Документ надо поднимать на верхний уровень
   user-сообщения.
4. **`deepseek-v4-pro` не видит изображения и не сообщает об этом.** Одна и та
   же картинка с числом: flash — `in=207`, ответ `4271`; v4-pro — `in=25`,
   картинка выброшена, ответ-галлюцинация. Запросы с картинками надо уводить на
   flash.
5. **Веб-поиск — серверный инструмент и платный отдельно.** Claude Code шлёт
   `web_search_20250305`, DeepSeek исполняет его сам и тарифицирует ¥5 за 1000
   вызовов. Счётчики приходят в `usage.server_tool_use.tool_search` и
   `tool_fetch`; если их не читать, учёт денег врёт.
6. **Claude Desktop игнорирует и переменные окружения, и managed-settings.**
   Проверено на Windows: `ANTHROPIC_BASE_URL` в процессе — ноль эффекта;
   `HKLM\SOFTWARE\Policies\ClaudeCode` со значениями `env` и `Settings` — ноль
   эффекта, в логе каждый раз `[managedConfig] type: 'none'`. Единственный
   рабочий путь — перехват TLS.
7. **Claude Desktop ставится как MSIX из Store.** Файлы в
   `C:\Program Files\WindowsApps\...` доступны только на чтение и заменяются
   обновлением. Патчить `app.asar` бессмысленно.

### 1.3 Деньги: токены, кэш, тарифные часы

Цены DeepSeek, юаней за 1M токенов (проверьте актуальные на странице тарифов):

| Модель | Кэш-хит | Кэш-промах | Выход |
|---|---|---|---|
| `deepseek-flash` | 0.02 / 0.04 | 1 / 2 | 4 / 8 |
| `deepseek-v4-pro` | 0.15 / 0.30 | 4.5 / 9 | 13.5 / 27 |

Через дробь — непиковый / пиковый тариф. Пик: Пн–Пт 09:00–12:00 и 14:00–18:00
по Пекину (UTC+8). Праздники КНР не учитываются, считаются непиковыми.

Кэш у DeepSeek автоматический, по префиксу; `cache_control` игнорируется.
Реальные замеры:

| Запрос | Вход | Из кэша | Цена (пик) |
|---|---|---|---|
| Claude Code, холодный | ~20 600 | 0 | ¥0.04 |
| Claude Code, следующий | ~260 | 20 480 | ¥0.002 |
| Claude Desktop, холодный | 49 463 | 0 | ¥0.10 |

Вывод: не дёргайте короткие `-p` вызовы в цикле и не меняйте системный промпт
без нужды — каждый такой чих сбрасывает префикс и стоит как холодный старт.

---

## 2. Что нужно до начала

- Node.js **22+** (`node --version`) — для Claude Code и шлюза.
- Ключ DeepSeek: https://platform.deepseek.com/api_keys (баланс должен быть > 0,
  иначе 402).
- Для части A и B — ничего кроме этого.
- Для части C — права администратора и Windows или macOS.
- Не ставьте ключ Anthropic и не логиньтесь в claude.ai: подписка в этой схеме
  не участвует, платит ключ DeepSeek.

---

## 3. Часть A — Claude Code на DeepSeek

### A1. Установка

Все ОС (проверено):

```bash
npm install -g @anthropic-ai/claude-code
claude --version        # ожидается 2.1.3xx
```

Альтернатива — нативный установщик Anthropic (`claude update` дальше обновляет
его сам). Если npm ругается на права, используйте менеджер версий Node
(`nvm`, `fnm`, `volta`), а не `sudo npm`.

### A2. Ключ

**Windows (PowerShell):**

```powershell
[Environment]::SetEnvironmentVariable('DEEPSEEK_API_KEY','sk-ВАШ_КЛЮЧ','User')
$env:DEEPSEEK_API_KEY = [Environment]::GetEnvironmentVariable('DEEPSEEK_API_KEY','User')
```

**macOS / Linux:**

```bash
echo 'export DEEPSEEK_API_KEY=sk-ВАШ_КЛЮЧ' >> ~/.zshrc   # или ~/.bashrc
source ~/.zshrc
```

### A3. Конфигурация

Проще всего — файл `~/.claude/settings.json` (все ОС, применяется всегда).
Ключ в нём лежит открытым текстом; если это неприемлемо, используйте вариант Б.

**Вариант А, settings.json:**

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://api.deepseek.com/anthropic",
    "ANTHROPIC_AUTH_TOKEN": "sk-ВАШ_КЛЮЧ",
    "ANTHROPIC_API_KEY": "",
    "ANTHROPIC_MODEL": "claude-sonnet-4-5[1m]",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "claude-opus-4-5",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "claude-sonnet-4-5[1m]",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "claude-haiku-4-5",
    "CLAUDE_CODE_SUBAGENT_MODEL": "claude-sonnet-4-5",
    "CLAUDE_CODE_EFFORT_LEVEL": "max",
    "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "786432"
  }
}
```

Windows: `%USERPROFILE%\.claude\settings.json`.
macOS/Linux: `~/.claude/settings.json`.

**Вариант Б, переменные окружения** (секрет не в файле):

```powershell
# Windows, на текущую сессию
$env:ANTHROPIC_BASE_URL   = 'https://api.deepseek.com/anthropic'
$env:ANTHROPIC_AUTH_TOKEN = $env:DEEPSEEK_API_KEY
$env:ANTHROPIC_API_KEY    = ''
$env:ANTHROPIC_MODEL      = 'claude-sonnet-4-5[1m]'
$env:ANTHROPIC_DEFAULT_OPUS_MODEL   = 'claude-opus-4-5'
$env:ANTHROPIC_DEFAULT_SONNET_MODEL = 'claude-sonnet-4-5[1m]'
$env:ANTHROPIC_DEFAULT_HAIKU_MODEL  = 'claude-haiku-4-5'
$env:CLAUDE_CODE_SUBAGENT_MODEL     = 'claude-sonnet-4-5'
```

```bash
# macOS / Linux
export ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic
export ANTHROPIC_AUTH_TOKEN="$DEEPSEEK_API_KEY"
export ANTHROPIC_API_KEY=""
export ANTHROPIC_MODEL='claude-sonnet-4-5[1m]'
export ANTHROPIC_DEFAULT_OPUS_MODEL='claude-opus-4-5'
export ANTHROPIC_DEFAULT_SONNET_MODEL='claude-sonnet-4-5[1m]'
export ANTHROPIC_DEFAULT_HAIKU_MODEL='claude-haiku-4-5'
export CLAUDE_CODE_SUBAGENT_MODEL='claude-sonnet-4-5'
```

Три поля, на которых спотыкаются все:

- `ANTHROPIC_API_KEY` **обязательно пустой**. Claude Code проверяет его первым;
  непустое значение перебивает `AUTH_TOKEN`.
- `ANTHROPIC_AUTH_TOKEN` уходит как `Authorization: Bearer` — именно это DeepSeek
  и ждёт.
- Имена моделей — только `claude-*`. Список известных имён зависит от версии
  клиента; если получаете `unrecognized_model`, проверьте, какие имена понимает
  ваша сборка (см. 7.2).

### A4. Проверка

Сначала API напрямую:

```bash
curl https://api.deepseek.com/anthropic/v1/messages \
  -H "Authorization: Bearer $DEEPSEEK_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"deepseek-flash","max_tokens":16,
       "messages":[{"role":"user","content":"Reply with exactly: OK"}]}'
```

Ожидается JSON с `"text":"OK"` и `"model":"deepseek-flash"`.

Затем клиент:

```bash
claude -p "Reply with just: OK" --output-format json --max-turns 1
```

Ожидается `"is_error":false`, `"result":"OK"`. В интерактиве `/status` должен
показать DeepSeek-эндпоинт, а `/model` — вашу модель.

### A5. Ежедневное использование

- `/model opus` → `deepseek-v4-pro`, `/model sonnet` → flash.
- Правки, Bash, Grep, субагенты, MCP, hooks, skills — работают как обычно.
- `claude -p "..." --output-format json` — для скриптов и автоматизации.

---

## 4. Часть B — локальный шлюз (рекомендуется)

Необязательна, но с ней вы видите, куда уходят деньги, и получаете обход
несовместимостей. Код лежит в папке `gateway/` этого проекта: два файла на
Node 22, без зависимостей (`server.mjs`, `config.json`).

### B1. Что даёт

- **Роутинг**: `opus` → `deepseek-v4-pro`; запросы без тулов (фоновые задачи
  Claude Code) → дешёвый flash с `effort=low` и выключенным thinking; всё
  остальное → `deepseek-flash[1m]`.
- **Логи**: `gateway/logs/requests.jsonl` — модель, токены, попадание в кэш,
  thinking-токены, цена, список тулов, ошибки.
- **Деньги**: считает по тарифам DeepSeek с учётом пиковых часов и кэша.
- **Защита зрения**: запрос с картинкой, ушедший на `v4-pro`, переводится на
  flash (иначе тихая галлюцинация).
- **PDF**: загружает документ в Files API, кэширует по SHA-256, подставляет
  `file_id` и поднимает блок из `tool_result` наверх.
- **Отказоустойчивость**: ретраи на 429/5xx, таймаут, дневной бюджет,
  `count_tokens` (у DeepSeek такого эндпоинта нет).

### B2. Запуск

```bash
cd gateway
node server.mjs          # слушает 127.0.0.1:8788
```

Ключ берётся из `DEEPSEEK_API_KEY`. Проверка:

```bash
curl http://127.0.0.1:8788/health
```

Затем в конфигурации Claude Code замените base URL:

```
ANTHROPIC_BASE_URL=http://127.0.0.1:8788
```

Токен при этом может быть любым: шлюз настроен на `auth: "gateway"` и
подставляет настоящий ключ сам.

### B3. Настройки

`gateway/config.json`:

| Поле | Смысл |
|---|---|
| `models.main/heavy/cheap` | какие модели соответствуют маршрутам |
| `routing.opusToHeavy` | `opus` в имени модели → тяжёлая модель |
| `routing.cheapWithoutTools` | запрос без тулов → дешёвый маршрут |
| `vision` | модели, которые видят картинки |
| `pricing` | цены за 1M токенов, peak/offPeak |
| `webPricing` | цена за 1000 поисков/фетчей |
| `limits.dailyBudget` | дневной лимит в валюте `currency`, 0 = выключено |

### B4. Отчёт по расходу

```bash
node gateway/report.mjs      # по дням и моделям
```

---

## 5. Часть C — Claude Desktop на DeepSeek (Windows / macOS)

### C1. Почему обычная настройка не работает

Приложение игнорирует всё, что могло бы перенаправить его «по-хорошему»:

- переменные окружения процесса (`ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`);
- `C:\Program Files\ClaudeCode\managed-settings.json` — это путь CLI;
- `HKLM\SOFTWARE\Policies\ClaudeCode` со значениями `env` и `Settings` — в логе
  приложения каждый раз `[managedConfig] type: 'none'`.

При этом режим стороннего провайдера в нём **есть**: в коде живут
`Custom3pApiKeySignIn`, тип `customEndpoint` и лог-префикс `[custom-3p]`.
Валидация ключа идёт запросом:

```
GET {base}/v1/models
x-api-key: <ваш ключ>
```

Если ответ не 200 — «That key wasn't accepted». Если 200, но список моделей не
содержит известных Anthropic-семейств — «0 usable models».

Отсюда стратегия: подменить DNS и TLS так, чтобы `{base}` стал нашим шлюзом.

### C2. Попытка 0 — managed-settings на macOS (5 минут)

На macOS в коде приложения указан собственный путь managed-настроек
(публичной документации на него нет, на живой машине не проверялся):

```bash
sudo mkdir -p /etc/claude-desktop
sudo tee /etc/claude-desktop/managed-settings.json >/dev/null <<'JSON'
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:8788",
    "ANTHROPIC_AUTH_TOKEN": "local-gateway",
    "ANTHROPIC_API_KEY": ""
  }
}
JSON
```

Перезапустите приложение и посмотрите лог
`~/Library/Logs/Claude/main.log` на строку `[managedConfig]`.
Если `type` не `none` — MITM не нужен, дальше просто введите любой ключ.
Если `none` — переходите к C3. (На Windows этот путь проверен и не сработал.)

### C3. Теория MITM

1. `api.anthropic.com` через `hosts` указывает на `127.0.0.1`.
2. На `127.0.0.1:443` слушает наш шлюз с сертификатом на `api.anthropic.com`.
3. Локальный CA добавлен в доверенные, поэтому клиент принимает сертификат.
4. Приложение думает, что говорит с Anthropic, а на деле говорит с DeepSeek.

Шлюз должен уметь:

- `GET /v1/models` → Anthropic-форма с `id` вида `claude-*` +
  `supports1m: true` для 1M-варианта;
- `POST /v1/messages` → проксирование в DeepSeek;
- `POST /v1/messages/count_tokens` → оценка (у DeepSeek такого эндпоинта нет);
- всё остальное → 404 (телеметрия, апдейтер, bootstrap — приложение терпит).

### C4. Windows

Нужны права администратора. Все команды — в PowerShell от админа, либо
сохраните как `setup-mitm.ps1` и запустите с `-Verb RunAs`.

**1. CA + сертификат + PFX**

```powershell
$here = 'C:\qclaude\mitm'; New-Item -ItemType Directory -Force $here | Out-Null

$ca = New-SelfSignedCertificate -Subject 'CN=QClaude Local CA' `
  -CertStoreLocation Cert:\LocalMachine\My `
  -KeyUsage CertSign, CRLSign, DigitalSignature `
  -TextExtension @('2.5.29.19={text}CA=true&pathlength=1') `
  -NotAfter (Get-Date).AddYears(5) -KeyExportPolicy Exportable

# доверяем CA: New-SelfSignedCertificate умеет писать только в My
$cer = Join-Path $here 'ca.cer'
Export-Certificate -Cert $ca -FilePath $cer -Type CERT | Out-Null
Import-Certificate -FilePath $cer -CertStoreLocation Cert:\LocalMachine\Root | Out-Null

$leaf = New-SelfSignedCertificate -Subject 'CN=api.anthropic.com' `
  -DnsName 'api.anthropic.com','*.anthropic.com' -Signer $ca `
  -CertStoreLocation Cert:\LocalMachine\My `
  -TextExtension @('2.5.29.19={text}CA=false','2.5.29.37={text}1.3.6.1.5.5.7.3.1') `
  -NotAfter (Get-Date).AddYears(2) -KeyExportPolicy Exportable

$pwd = ConvertTo-SecureString -String 'qclaude' -AsPlainText -Force
Export-PfxCertificate -Cert $leaf -FilePath (Join-Path $here 'api.anthropic.com.pfx') -Password $pwd | Out-Null
```

**2. hosts**

```powershell
$hosts = "$env:SystemRoot\System32\drivers\etc\hosts"
Add-Content $hosts "`r`n# qclaude-mitm`r`n127.0.0.1 api.anthropic.com`r`n"
```

**3. Шлюз с TLS**

```powershell
$env:DEEPSEEK_API_KEY     = 'sk-ВАШ_КЛЮЧ'
$env:GATEWAY_TLS_PFX      = 'C:\qclaude\mitm\api.anthropic.com.pfx'
$env:GATEWAY_TLS_PASSPHRASE = 'qclaude'
node gateway\server.mjs
```

В логе должно появиться:

```
Gateway  http://127.0.0.1:8788
TLS      https://api.anthropic.com:443
```

**4. Проверка перехвата (до приложения)**

```powershell
curl.exe -s --ssl-no-revoke https://api.anthropic.com/v1/models -H "x-api-key: dummy"
```

`--ssl-no-revoke` нужен только curl'у: schannel не умеет проверять отзыв у
локального CA. Chromium/Electron это не мешает. Ожидается наш JSON со списком
`claude-*`.

**5. Вход в приложение**

Перезапустите Claude Desktop и введите **любой** ключ вида `sk-ant-...`,
например `sk-ant-gateway-test`. Шлюз подставит настоящий ключ DeepSeek сам.
Пароль не нужен, claude.ai не участвует.

### C5. macOS

Проверено частично: шаги стандартные, но на живой машине не прогонялись.
Официального Claude Desktop для Linux нет.

**1. CA и сертификат**

```bash
mkdir -p ~/qclaude-mitm && cd ~/qclaude-mitm

openssl req -x509 -newkey rsa:2048 -nodes -days 1825 \
  -keyout ca.key -out ca.crt -subj "/CN=QClaude Local CA" \
  -addext "basicConstraints=critical,CA:TRUE,pathlen:1" \
  -addext "keyUsage=critical,keyCertSign,cRLSign"

openssl req -newkey rsa:2048 -nodes -keyout api.key -out api.csr \
  -subj "/CN=api.anthropic.com"

cat > api.ext <<'EOF'
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:api.anthropic.com,DNS:*.anthropic.com
EOF

openssl x509 -req -in api.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out api.crt -days 730 -extfile api.ext
```

**2. Доверие и hosts**

```bash
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain ~/qclaude-mitm/ca.crt

echo "127.0.0.1 api.anthropic.com" | sudo tee -a /etc/hosts
```

**3. Шлюз** (порт 443 требует root)

```bash
sudo DEEPSEEK_API_KEY=sk-ВАШ_КЛЮЧ \
  GATEWAY_TLS_CERT="$HOME/qclaude-mitm/api.crt" \
  GATEWAY_TLS_KEY="$HOME/qclaude-mitm/api.key" \
  node gateway/server.mjs
```

**4. Проверка и вход**

```bash
curl -s https://api.anthropic.com/v1/models -H "x-api-key: dummy"
open -a Claude
```

Ввести `sk-ant-gateway-test`.

### C6. Что должно получиться

В логе шлюза:

```
GET  /v1/models   200
POST /v1/messages 200  main  deepseek-flash[1m]  in=49463  out=253
```

49 463 входных токена — это системный промпт десктопа плюс его тулсет
(`Agent`, `Artifact`, `AskUserQuestion`, `Bash`, `Edit`, ...). Первый ход стоит
≈¥0.10 на пиковом тарифе, последующие дешевле за счёт кэша.

Служебные 404 (`/api/event_logging/v2/batch`, `metrics_enabled`, `bootstrap`,
`policy_limits`, проверка обновлений) — норма. Приложение их игнорирует;
телеметрия и автообновление просто не работают.

### C7. Откат

**Windows (админ):**

```powershell
$hosts = "$env:SystemRoot\System32\drivers\etc\hosts"
(Get-Content $hosts) | Where-Object { $_ -notmatch 'qclaude-mitm' -and $_ -notmatch '^\s*127\.0\.0\.1\s+api\.anthropic\.com' } | Set-Content $hosts -Encoding ASCII
Get-ChildItem Cert:\LocalMachine\My   | Where-Object { $_.Subject -eq 'CN=api.anthropic.com' } | Remove-Item -Force
Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -eq 'CN=QClaude Local CA' }  | Remove-Item -Force
```

**macOS:**

```bash
sudo sed -i '' '/api.anthropic.com/d' /etc/hosts
sudo security delete-certificate -c "QClaude Local CA" /Library/Keychains/System.keychain
```

После отката перезапустите приложение и проверьте, что `api.anthropic.com`
снова резолвится в интернет.

---

## 6. Чек-лист приёмки

| # | Проверка | Ожидание |
|---|---|---|
| 1 | `curl` к `/anthropic/v1/messages` | `"text":"OK"`, `model=deepseek-flash` |
| 2 | `claude -p "say OK"` | `is_error:false` |
| 3 | `claude -p "read README.md"` | ответ по содержимому файла |
| 4 | Субагент / skill / MCP (если нужны) | работают, см. `parity/run-parity.ps1` |
| 5 | `curl http://127.0.0.1:8788/health` | `{"ok":true,...}` |
| 6 | `curl --ssl-no-revoke https://api.anthropic.com/v1/models` | JSON с `claude-*` |
| 7 | Логин в десктопе | пускает, чат отвечает |

---

## 7. Если не работает

### 7.1 Ошибки API

| Симптом | Причина | Лечение |
|---|---|---|
| `API Error: Invalid URL` | base URL без схемы | добавить `https://` |
| `unrecognized_model` | имя модели не `claude-*` | см. 7.2 |
| `401 invalid x-api-key` | ключ не доехал | проверить `AUTH_TOKEN`, пустой `API_KEY` |
| `402` | нет баланса | пополнить |
| 400 про `document`/`source` | инлайновый документ | Files API (`source.type: file`) |
| Модель отвечает `NO-DOCUMENT` | документ в `tool_result` | поднять на верхний уровень |
| Модель «не видит» картинку | запрос ушёл на `v4-pro` | увести на flash |

### 7.2 Как узнать допустимые имена моделей

Валидация клиентская, список зависит от версии. Быстрый перебор: подставьте имя
и запустите `claude -p "OK"`. Отказ `unrecognized_model` приходит **до** запроса
к API — такой перебор бесплатен. Рабочие на 2.1.326:
`claude-sonnet-4-5`, `claude-sonnet-4-5[1m]`, `claude-opus-4-5`,
`claude-haiku-4-5`. Не работают: `deepseek-flash`, `deepseek-v4-pro`,
`claude-opus-4-1`.

### 7.3 Десктоп

| Симптом | Где смотреть | Причина |
|---|---|---|
| «That key wasn't accepted» | `main.log`, `[custom-3p]` | запрос ушёл не к нам: hosts/сертификат |
| `[managedConfig] type: 'none'` | `main.log` | managed-settings не читаются (норма для Windows) |
| Ошибка сертификата | `main.log`, `ERR_CERT_*` | CA не в доверенных или SAN не тот |
| «0 usable models» | лог шлюза | `/v1/models` вернул не `claude-*` |
| `TLS client error: socket hang up` | лог шлюза | клиент отверг сертификат (чаще всего — недоверенный CA) |
| Пусто после логина | лог шлюза, 404 | не реализован нужный эндпоинт — добавить заглушку |

### 7.4 Диагностика шлюза

```bash
curl http://127.0.0.1:8788/health           # жив ли
tail -f gateway/logs/requests.jsonl         # что приходит
GATEWAY_DUMP=1 node gateway/server.mjs      # писать последний payload в logs/last-request.json
```

---

## 8. Ограничения

- Anthropic официально не поддерживает Claude Code и Desktop с не-Claude
  моделями; обновление клиента может сломать конфигурацию.
- `deepseek-v4-pro` не видит изображения; `deepseek-flash` видит.
- PDF: только через Files API, до 20 документов на запрос и 8 MiB текста,
  парсинг ¥1.5 за 1000 страниц, скачать распознанный текст нельзя.
- MCP tool-use блоки и результаты code execution DeepSeek не поддерживает.
- Веб-поиск платный отдельно: ¥5 за 1000 вызовов.
- Claude Desktop: телеметрия и автообновление не работают (404), Linux-версии
  нет, Store-обновление может поменять протокол.
- Автокомпакция на 768K не проверялась: чтобы её вызвать, нужно прогнать почти
  миллион токенов контекста.

---

## 9. Безопасность и условия

- Локальный CA даёт возможность перехватывать **весь** трафик к
  `api.anthropic.com` на этой машине. Держите приватный ключ CA закрытым,
  удаляйте сертификат после эксперимента.
- Перенаправление официального клиента на сторонний API почти наверняка
  нарушает условия использования Anthropic. Это локальный эксперимент, не
  продукт.
- Ключ DeepSeek — деньги. Не коммитьте его в git; в `settings.json` он лежит
  открытым текстом, учитывайте это.
- Всё обратимо: часть C снимается разделом C7, части A и B — удалением
  переменных окружения.

---

## Приложение A. Что реально уходит в запросе

Снято дампом `GATEWAY_DUMP=1` с Claude Code 2.1.326:

- `system` — 3 текстовых блока: billing-заголовок (74 Б), идентичность
  «You are a Claude agent, built on Anthropic's Claude Agent SDK» (62 Б),
  инструкции (27 045 Б ≈ 7.5K токенов).
- `tools` — 14 схем, ~50 КБ ≈ 14K токенов: `Agent`, `Bash`, `Edit`, `Glob`,
  `Grep`, `ListAgents`, `Read`, `ReportFindings`, `ScheduleWakeup`, `Skill`,
  `ToolSearch`, `Workflow`, `DeferredToolPlaceholder`, `Write`.
- `thinking` — `{budget_tokens: 31999, type: enabled, display_omitted}`,
  `max_tokens: 32000`.
- `metadata.user_id` — `device_id`, `session_id`, пустой `account_uuid`.

У десктопа тот же системный промпт, но тулсет шире (`Artifact`,
`AskUserQuestion` и др.) и вход ~49K токенов.

## Приложение B. Файлы этого проекта

| Файл | Назначение |
|---|---|
| `env.ps1` | переменные окружения для Claude Code |
| `qclaude.ps1` | запуск CLI напрямую |
| `qclaude-gw.ps1` | запуск CLI через шлюз, с автозапуском |
| `test-connection.ps1` | проверка ключа одним запросом |
| `gateway/server.mjs` | шлюз: роутинг, логи, деньги, PDF, vision-guard, TLS |
| `gateway/config.json` | маршруты, тарифы, лимиты |
| `gateway/report.mjs` | отчёт по расходу |
| `parity/` | стенд проверки фич Claude Code (MCP, hooks, skills, субагенты) |
| `desktop/mitm/` | установка и снятие MITM для Claude Desktop |
