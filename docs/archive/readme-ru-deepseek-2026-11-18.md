# QClaudeCode

Настоящий Claude Code (без форка и патчей) на моделях DeepSeek — напрямую или
через локальный шлюз с логами, роутингом и учётом денег.

## Статус: проверено на Claude Code 2.1.326

| Проверка | Результат |
|---|---|
| Прямой запрос к `/v1/messages` | `model=deepseek-flash`, 35 in / 16 out |
| Запуск Claude Code | `deepseek-flash[1m] · API Usage Billing` |
| Headless + тулы `Read`, `Glob` | `turns=2`, ответ верный |
| Шлюз: обычный запрос / стриминг | 200, 7 SSE-событий, usage снят |
| Шлюз: автозапуск | поднялся сам, `qclaude-gw.ps1` отработал |
| Кэш DeepSeek | 20 608 из 20 736 входных токенов — из кэша |
| Vision | flash читает `4271` с картинки (`in=207`), v4-pro — нет (`in=25`) |
| Web search | Claude Code шлёт `web_search_20250305`, DeepSeek исполняет (`web=1`) |
| Documents | PDF через Files API: `file_id` + подъём из `tool_result`, ответ `4271` |
| Цена (непиковый тариф) | ¥0.0209 промах кэша / ¥0.0007 попадание |

## Быстрый старт

```powershell
cd D:\Startup\QClaudeCode
.\test-connection.ps1      # проверить ключ (спросит один раз, скрыто)
.\qclaude.ps1              # напрямую в DeepSeek
.\qclaude-gw.ps1           # через локальный шлюз (логи, роутинг, деньги)
```

Ключ хранится в пользовательской переменной `DEEPSEEK_API_KEY`. Удалить:
`[Environment]::SetEnvironmentVariable('DEEPSEEK_API_KEY',$null,'User')`.

## Шлюз

```
Claude Code -> http://127.0.0.1:8788/v1/messages -> api.deepseek.com/anthropic
```

`qclaude-gw.ps1` сам проверяет `/health` и поднимает шлюз, если тот не запущен.
Управление вручную:

```powershell
.\gateway\start.ps1          # в форграунде, Ctrl+C
.\gateway\start.ps1 -Stop    # погасить фоновый
node gateway\report.mjs      # расход по дням и моделям
```

Что шлюз делает поверх обычного `ANTHROPIC_BASE_URL`:

- **Роутинг.** `opus` в имени модели → `deepseek-v4-pro`; запрос без тулов
  (фоновые задачи Claude Code: заголовки, проверки) → дешёвый flash с
  `effort=low` и выключенным thinking; всё остальное → `deepseek-flash[1m]`.
  Маршрут виден в заголовке ответа `x-gateway-route`.
- **Логи.** `gateway/logs/requests.jsonl`: модель, маршрут, токены, попадание в
  кэш, thinking-токены, цена, список тулов, ошибки.
- **Защита от слепой модели.** Если в запросе есть картинка, а маршрут ведёт на
  `v4-pro`, шлюз переводит его на flash: v4-pro изображения молча игнорирует.
  В логе это видно как `images: heavy->main`.
- **PDF через Files API.** Инлайновый `document` загружается в `/files`
  (`rich_layout_recognition`), кэшируется по SHA-256 и подставляется как
  `file_id`. Claude Code присылает документ внутри `tool_result`, где DeepSeek
  его не видит, — шлюз поднимает блок на верхний уровень сообщения.
- **Учёт веб-поиска.** Один серверный поиск стоит ¥0.005 независимо от токенов.
  Шлюз читает `usage.server_tool_use` и добавляет это к цене запроса; в логе
  видно `web=1/0`.
- **Деньги.** Считает по реальным тарифам DeepSeek: пиковые/непиковые часы
  (Пн–Пт 09:00–12:00 и 14:00–18:00 по Пекину), отдельная цена за кэш.
- **Санитайз.** Вырезает `cache_control`, заменяет инлайновые `document`-блоки
  текстовой заглушкой (DeepSeek принимает их только через Files API).
- **Отказоустойчивость.** Ретраи на 429/5xx, таймаут 10 минут, опциональный
  дневной бюджет (`limits.dailyBudget`, 0 = выключено).
- **`count_tokens`.** У DeepSeek такого эндпоинта нет, шлюз отдаёт оценку —
  иначе у Claude Code ломается индикатор контекста.

Настройки — `gateway/config.json`. Цены там в юанях; если ваш аккаунт биллится
в долларах, поменяйте `currency` и цифры.

## Файлы

| Файл | Назначение |
|---|---|
| `env.ps1` | Выставляет `ANTHROPIC_*`, при первом запуске спрашивает ключ |
| `qclaude.ps1` | Claude Code напрямую в DeepSeek |
| `qclaude-gw.ps1` | То же через шлюз, с автозапуском |
| `test-connection.ps1` | Один дешёвый запрос, проверка ключа |
| `gateway/server.mjs` | Шлюз, Node 22, без зависимостей |
| `gateway/config.json` | Маршруты, тарифы, лимиты |
| `gateway/start.ps1` | Запуск/остановка шлюза |
| `gateway/report.mjs` | Отчёт по расходу |

## Грабли, на которые уже наступили

1. **Base URL без схемы не работает.** `api.deepseek.com/anthropic` из
   документации даёт `API Error: Invalid URL`. Нужен `https://`.
2. **Имя модели обязано начинаться с `claude`.** На `deepseek-flash` Claude Code
   отвечает `claude-code:unrecognized_model` ещё до запроса к API. Маппинг на
   стороне DeepSeek: `claude-opus*` → `deepseek-v4-pro`, остальные `claude*` →
   `deepseek-flash`, суффикс `[1m]` — контекст 1M.
3. **`-p` съедался параметром скрипта.** В лаунчерах нет блока `param()` —
   иначе PowerShell трактует `-p <промпт>` как их параметр.
4. **`$ErrorActionPreference='Stop'` + нативный exe.** Любая запись в stderr от
   `claude.exe` превращается в terminating error и убивает лаунчер.
5. **PowerShell 5.1 пишет BOM в UTF-8.** `JSON.parse` на таком теле падает;
   шлюз срезает BOM на входе.
6. **`document` внутри `tool_result` не работает.** DeepSeek читает документы
   только с верхнего уровня user-сообщения: тот же `file_id`, положенный в
   `tool_result`, даёт `NO-DOCUMENT`, а рядом с ним — верный ответ. Изображения
   при этом во вложении работают (проверено). Шлюз поднимает документы наверх.

## Маппинг моделей

| Переменная | Значение | Реально обслуживает |
|---|---|---|
| `ANTHROPIC_BASE_URL` | `https://api.deepseek.com/anthropic` | весь трафик в DeepSeek |
| `ANTHROPIC_AUTH_TOKEN` | ключ DeepSeek | уходит как `Authorization: Bearer` |
| `ANTHROPIC_API_KEY` | пусто | иначе Claude Code предпочтёт его |
| `ANTHROPIC_MODEL` | `claude-sonnet-4-5[1m]` | `deepseek-flash`, 1M контекст |
| `..._OPUS_MODEL` | `claude-opus-4-5` | `deepseek-v4-pro` |
| `..._SONNET_MODEL` | `claude-sonnet-4-5[1m]` | `deepseek-flash` |
| `..._HAIKU_MODEL` | `claude-haiku-4-5` | `deepseek-flash`, фоновые задачи |
| `CLAUDE_CODE_SUBAGENT_MODEL` | `claude-sonnet-4-5` | субагенты `Task` |
| `CLAUDE_CODE_EFFORT_LEVEL` | `max` | глубина рассуждений |
| `CLAUDE_CODE_AUTO_COMPACT_WINDOW` | `786432` | автокомпакция на 768K из 1M |

`/model opus` переключает на `deepseek-v4-pro`, `/model sonnet` — обратно.

## Цена

Тарифы DeepSeek (CNY за 1M токенов, непиковый / пиковый):

| | кэш-хит | кэш-промах | выход |
|---|---|---|---|
| `deepseek-flash` | 0.02 / 0.04 | 1 / 2 | 4 / 8 |
| `deepseek-v4-pro` | 0.15 / 0.30 | 4.5 / 9 | 13.5 / 27 |

Главный вывод из живых замеров: холодный запрос Claude Code (~20.6K входных
токенов системного промпта и схем тулов) стоит **¥0.0209**, а следующий за ним
с тем же префиксом — **¥0.0007**. Разница в 30 раз, потому что почти всё уходит
в кэш. Отсюда практика: не гонять короткие `-p` вызовы в цикле и не менять
системный промпт без нужды — это сбрасывает кэш.

## Ограничения

- **`deepseek-v4-pro` не видит изображения и не сообщает об этом.** Одна и та же
  картинка с числом `4271`: flash — `in=207`, верный ответ; v4-pro — `in=25`
  (картинка вообще не попала в запрос) и поток галлюцинаций. Ошибки нет, есть
  тихо неверный ответ. Шлюз поэтому уводит запросы с картинками на flash
  (`images: heavy->main` в логе), даже если выбран `opus`.
- **PDF инлайном не отправляется.** `document` с `source.type: base64` даёт 400:
  DeepSeek принимает только `file` (через Files API) и `text`; шлюз загружает
  файл сам. Ограничения: до 20 документов на запрос, до 8 MiB текста в них,
  парсинг платный (¥1.5 за 1000 страниц, списывается при загрузке). Скачать
  распознанный текст нельзя — только ответы модели по документу.
- **Document parsing и OCR не подключены.** PDF по-прежнему требует Files API.
  Отдельный OCR-эндпоинт для скриншотов не нужен: flash читает текст с картинки
  сам (проверено на `4271`). Он полезен для сканов и пакетной обработки страниц.
- Anthropic официально не поддерживает Claude Code с не-Claude моделями.
  Обновление Claude Code может сломать конфиг (allowlist имён уже пришлось
  обходить). Откат бесплатный — не запускать лаунчер.
- `count_tokens` в шлюзе оценочный (символы / 3.6), индикатор контекста
  приблизительный.
- Праздники КНР не учитываются в пиковых часах, они считаются непиковыми.
- MCP tool-use блоки и результаты code execution DeepSeek не поддерживает.

## Тюнинг

```powershell
$env:API_TIMEOUT_MS = '600000'
$env:DISABLE_NON_ESSENTIAL_MODEL_CALLS = '1'
```

## Дальше

Десктоп: DeepSeek Harness (`npx @deepseek-ai/dsh web`) или Claude Agent SDK
с тем же `ANTHROPIC_BASE_URL` — шлюз подойдёт и туда без изменений.
