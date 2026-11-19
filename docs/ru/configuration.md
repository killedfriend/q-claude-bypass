# Конфигурация

> **Учебный некоммерческий проект.** Примеры конфигурации предназначены для
> обучения. Ответственность за условия провайдеров, расходы и обработку данных
> лежит на вас.

## Файлы

| Файл | Назначение |
|---|---|
| `gateway/config.json` | Общие настройки: порт, публичные модели, маршрутизация, контекст, лимиты |
| `gateway/providers/<id>.json` | Провайдер: upstream, аутентификация, модели, цены, возможности |
| `%USERPROFILE%\.claude\settings.json` | Окружение Claude Code |
| `%USERPROFILE%\.claude.json` | Состояние onboarding Claude Code |
| `gateway/logs/requests.jsonl` | Один JSON-объект на запрос |
| `gateway/logs/gateway.pid` | PID работающего шлюза |
| `gateway/logs/last-request.json` | Полный запрос, только при `GATEWAY_DUMP=1` |

Переменные окружения:

| Переменная | Действие |
|---|---|
| `GATEWAY_PROVIDER` | ID провайдера, переопределяет `config.json` |
| `GATEWAY_PORT` | Порт |
| `GATEWAY_HOST` | Адрес прослушивания (оставьте `127.0.0.1`) |
| `GATEWAY_UPSTREAM` | Переопределить upstream провайдера |
| `GATEWAY_LOG` | Переопределить путь лога |
| `GATEWAY_MAX_CHARS` | Порог размера контекста для обрезки |
| `GATEWAY_DUMP` | `1` — записывать полный запрос наверх |
| `GATEWAY_TLS_PFX`, `GATEWAY_TLS_PASSPHRASE` | TLS-слушатель для MITM на Windows |
| `GATEWAY_TLS_CERT`, `GATEWAY_TLS_KEY` | TLS-слушатель из PEM |

## Общий конфиг

```json
{
  "version": 2,
  "provider": "deepseek",
  "listen": { "host": "127.0.0.1", "port": 8788 },
  "logFile": "logs/requests.jsonl",
  "publicModels": [
    "claude-sonnet-4-5[1m]",
    "claude-opus-4-5",
    "claude-haiku-4-5"
  ],
  "routing": {
    "opusToHeavy": true,
    "haikuToCheap": true,
    "cheapWithoutTools": true
  },
  "context": {
    "enabled": true,
    "maxChars": 500000,
    "keepRecentToolResults": 8,
    "elideAboveChars": 4000
  },
  "limits": {
    "dailyBudget": 0,
    "maxRetries": 2,
    "timeoutMs": 600000
  }
}
```

| Ключ | Значение |
|---|---|
| `provider` | ID пресета из `gateway/providers/` |
| `listen.host` | Адрес. Оставьте loopback, если не добавили аутентификацию |
| `listen.port` | По умолчанию 8788 |
| `publicModels` | Модели, которые видят Claude Code и Desktop. Держите имена похожими на Claude |
| `routing.opusToHeavy` | Запросы с `opus` идут на `models.heavy` |
| `routing.haikuToCheap` | Запросы с `haiku` идут на `models.cheap` |
| `routing.cheapWithoutTools` | Запросы без инструментов идут на `models.cheap` |
| `context.maxChars` | Порог размера тела перед обрезкой |
| `context.keepRecentToolResults` | Сколько последних результатов инструментов не трогать |
| `context.elideAboveChars` | Обрезать только результаты длиннее этого |
| `limits.dailyBudget` | Дневной лимит в валюте провайдера; `0` — выключено |
| `limits.maxRetries` | Повторы на 408/429/5xx |
| `limits.timeoutMs` | Жёсткий таймаут запроса |

## Конфиг провайдера

```json
{
  "name": "OpenRouter",
  "docs": "https://openrouter.ai/",
  "upstream": "https://openrouter.ai/api",
  "currency": "USD",
  "auth": {
    "mode": "gateway",
    "header": "authorization",
    "scheme": "Bearer ",
    "env": "OPENROUTER_API_KEY"
  },
  "headers": { "X-Title": "QClaude Code" },
  "models": {
    "main": "anthropic/claude-sonnet-4.5",
    "heavy": "anthropic/claude-opus-4.5",
    "cheap": "anthropic/claude-haiku-4.5"
  },
  "vision": ["anthropic/claude-sonnet-4.5"],
  "documents": "native",
  "cheapProfile": { "maxTokens": 4096 },
  "pricing": {
    "anthropic/claude-sonnet-4.5": { "input": 3, "cacheRead": 0.3, "output": 15 }
  },
  "client": {
    "direct":  { "model": "...", "opus": "...", "sonnet": "...", "haiku": "...", "subagent": "..." },
    "gateway": { "model": "claude-sonnet-4-5[1m]", "opus": "claude-opus-4-5", "sonnet": "claude-sonnet-4-5[1m]", "haiku": "claude-haiku-4-5", "subagent": "claude-sonnet-4-5" }
  }
}
```

| Ключ | Значение |
|---|---|
| `upstream` | Базовый URL без `/v1/messages` |
| `currency` | `CNY`, `USD`, `EUR`; используется в логах и отчётах |
| `auth.mode` | `gateway` — ключ из окружения; `passthrough` — ключ клиента |
| `auth.header` | `authorization` или `x-api-key` |
| `auth.scheme` | `Bearer ` или пустая строка |
| `auth.env` | Переменная окружения с ключом |
| `headers` | Дополнительные заголовки наверх |
| `models` | Реальные ID моделей для `main`, `heavy`, `cheap` |
| `vision` | Модели, которые принимают изображения |
| `documents` | `deepseek-files`, `native` или `none` |
| `cacheControl` | `strip` (по умолчанию) или `keep`; только если провайдер поддерживает |
| `cheapProfile` | Изменения для дешёвых вызовов: `effort`, `thinking`, `maxTokens` |
| `pricing` | За 1M токенов; возможны `peak`/`offPeak` |
| `client.direct` | Имена для `qclaude.ps1` (прямой режим) |
| `client.gateway` | Имена для `qclaude-gw.ps1` (публичные имена Claude) |

## Маршрутизация

Порядок:

1. В имени есть `opus`, и `opusToHeavy` включён → `heavy`.
2. Иначе есть `haiku`, и `haikuToCheap` включён → `cheap`.
3. Иначе нет инструментов, и `cheapWithoutTools` включён → `cheap`.
4. Иначе → `main`.

Затем:

- Если в запросе есть изображение, а выбранная модель не в `vision`, шлюз
  пробует `main`. Если и `main` не умеет изображения, запрос проходит, а в лог
  пишется `images: no vision-capable model configured`.
  Заголовок `x-gateway-route` показывает маршрут, `x-gateway-model` — реальную
  модель.

Для дешёвых вызовов применяется `cheapProfile`:

```json
{ "effort": "low", "thinking": "disabled", "maxTokens": 4096 }
```

Добавляйте `effort`/`thinking`, только если провайдер принимает эти поля.

## Обрезка контекста

Длинные агентские сессии каждый ход пересылают весь транскрипт. Когда
`JSON.stringify(body).length` превышает `context.maxChars`, шлюз заменяет текст
самых старых блоков `tool_result` на:

```text
[tool output elided by gateway: 12345 chars]
```

Сообщения и пары `tool_use`/`tool_result` никогда не удаляются. Преобразование
детерминированное, поэтому префиксный кэш провайдера продолжает работать.

Отключение:

```json
{ "context": { "enabled": false } }
```

Настройка на запуск:

```powershell
$env:GATEWAY_MAX_CHARS = '300000'
```

Обрезка экономит деньги, но может убрать нужную модель информацию. Увеличьте
`keepRecentToolResults`, если модель начинает просить уже прочитанные файлы.

## Цены и стоимость

`pricing` — за 1 миллион токенов в валюте провайдера:

```json
{
  "model-id": { "input": 3, "cacheRead": 0.3, "output": 15 }
}
```

DeepSeek поддерживает тарифные часы:

```json
{
  "deepseek-flash": {
    "peak":    { "cacheRead": 0.04, "input": 2, "output": 8 },
    "offPeak": { "cacheRead": 0.02, "input": 1, "output": 4 }
  }
}
```

Формула:

```text
(input_tokens * input + cache_read_tokens * cacheRead + output_tokens * output) / 1e6
```

Если провайдер вернул `usage.cost` (OpenRouter), используется точное значение.
Веб-поиск добавляется за вызов по `webPricing` (только DeepSeek).
Если цены нет, `cost: null`, а не ноль; отчёт печатает `-`.

Дневной бюджет проверяется до запроса:

```json
{ "limits": { "dailyBudget": 5 } }
```

`5` — пять единиц `currency` на локальный день. Записи в другой валюте в бюджет
не входят.

## Логи

Каждая строка `requests.jsonl`:

```json
{
  "ts": "2026-11-19T12:00:00.000Z",
  "day": "2026-11-19",
  "provider": "openrouter",
  "currency": "USD",
  "route": "main",
  "reqModel": "claude-sonnet-4-5[1m]",
  "upModel": "anthropic/claude-sonnet-4.5",
  "status": 200,
  "ms": 1234,
  "stream": true,
  "in": 1234,
  "cacheRead": 1000,
  "out": 56,
  "thinking": 0,
  "cost": 0.0042,
  "upCost": 0.0042,
  "tools": ["Read", "Bash"],
  "toolTypes": ["custom"],
  "applied": [],
  "notes": [],
  "err": null
}
```

Тексты промптов и ответов не сохраняются. Имена инструментов и фрагменты ошибок
сохраняются. `GATEWAY_DUMP=1` пишет полный запрос в `logs/last-request.json`,
включая промпты и данные файлов; считайте этот файл чувствительным.

Отчёт:

```powershell
node gateway\report.mjs        # последние 14 дней
node gateway\report.mjs 30     # последние 30 дней
```

## Настройки клиента

`qclaude-gw.ps1` задаёт окружение процесса:

```text
ANTHROPIC_BASE_URL=http://127.0.0.1:8788
ANTHROPIC_AUTH_TOKEN=local-gateway
ANTHROPIC_API_KEY=
```

`ANTHROPIC_API_KEY` должен быть пустым, иначе Claude Code может предпочесть его
`ANTHROPIC_AUTH_TOKEN`.

Установленный `~/.claude/settings.json` использует те же значения, поэтому
обычный `claude` в новом терминале тоже идёт через шлюз. Удалить ключи можно
через `uninstall.ps1`.

## Эндпоинты

| Метод | Путь | Назначение |
|---|---|---|
| `GET` | `/` или `/health` | Здоровье, провайдер, маршруты, расход, наличие ключа |
| `GET` | `/v1/models` | Список моделей в форме Claude для Desktop |
| `POST` | `/v1/messages` | Прокси Anthropic Messages |
| `POST` | `/v1/messages/count_tokens` | Локальная оценка токенов |

Пример `/health`:

```json
{
  "ok": true,
  "provider": "deepseek",
  "upstream": "https://api.deepseek.com/anthropic",
  "requests": 12,
  "errors": 0,
  "currency": "CNY",
  "spentToday": 0.0312,
  "keyConfigured": true,
  "routes": { "main": "deepseek-flash[1m]", "heavy": "deepseek-v4-pro", "cheap": "deepseek-flash" }
}
```

## Автозапуск

Установщик пишет пользовательскую запись:

```text
HKCU\Software\Microsoft\Windows\CurrentVersion\Run\QClaudeGateway
```

Она запускает `gateway\autostart.ps1`, который проверяет `/health` и при
необходимости стартует Node скрыто. Запросы пишутся в
`gateway\logs\requests.jsonl`; ошибки запуска видны при запуске
`gateway\start.ps1` в терминале. Права администратора и служба Windows не
нужны.

Если существует `desktop\mitm\api.anthropic.com.pfx`, `gateway\gw-env.ps1`
автоматически выставляет `GATEWAY_TLS_PFX`, и шлюз дополнительно слушает
`https://127.0.0.1:443` для MITM Claude Desktop. Удалите PFX (или выполните
`desktop\mitm\teardown-mitm.ps1`) и перезапустите шлюз, чтобы отключить.

Отключение:

```powershell
Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name QClaudeGateway
```

Альтернативный вариант с планировщиком — `desktop\install-autostart.ps1`.

## Безопасность

- Держите `listen.host` на `127.0.0.1`.
- При `auth.mode: gateway` шлюз игнорирует ключ клиента; любой локальный процесс
  может им пользоваться. Это нормально для одного пользователя, но не для
  общего компьютера.
- Ключи хранятся в пользовательских переменных. Не коммитьте `.env` и файлы
  провайдеров с ключами.
- Логи содержат метаданные. Дампы содержат содержимое.
- MITM устанавливает локальный CA и меняет `hosts`; понимайте риски и
  откатывайтесь через `teardown-mitm.ps1`.
