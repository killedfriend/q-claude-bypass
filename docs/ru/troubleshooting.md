# Диагностика

> **Учебный некоммерческий проект.** Диагностика может показать промпты,
> содержимое файлов и метаданные API. Проверяйте логи перед публикацией.
> Используйте на свой риск.

## Первые пять проверок

```powershell
# 1. Шлюз жив?
Invoke-RestMethod http://127.0.0.1:8788/health

# 2. Какой провайдер и маршруты?
(Invoke-RestMethod http://127.0.0.1:8788/health) | Format-List

# 3. Что было в последнем запросе?
Get-Content gateway\logs\requests.jsonl -Tail 1

# 4. Какой статус и ошибка в последнем запросе?
(Get-Content gateway\logs\requests.jsonl -Tail 1 | ConvertFrom-Json) | Select-Object status, err

# 5. Ключ провайдера работает напрямую?
.\test-connection.ps1
```

Если `/health` не отвечает, шлюз не запущен:

```powershell
.\gateway\start.ps1 -Background
```

Или запустите в форграунде, чтобы увидеть ошибки:

```powershell
.\gateway\start.ps1
```

## 401 / 403 / invalid API key

Симптомы: `authentication_error`, `invalid_api_key`, `AccessDenied`, HTTP 401
или 403 в логе.

Причины и решения:

1. **Ключа нет в окружении процесса.** Откройте новый терминал после установки
   или задайте явно:
   ```powershell
   $env:DASHSCOPE_API_KEY = 'sk-...'
   ```
2. **Ключ не того типа.** У Alibaba ключи оплаты по запросам, Coding Plan и
   Token Plan не взаимозаменяемы. Сверьте тип ключа и base URL.
3. **Неверный заголовок.** DeepSeek и Alibaba используют
   `Authorization: Bearer`; пресет Tencent — `x-api-key`. Проверьте
   `auth.header` и `auth.scheme`.
4. **Ключ отключён или кончились деньги.** Проверьте консоль провайдера.
5. **В ключе пробелы или кавычки.** Введите заново через скрытый ввод, без
   кавычек.

Проверка без Claude Code:

```powershell
.\test-connection.ps1
```

## `claude-code:unrecognized_model`

Некоторые версии Claude Code проверяют имя модели. Публичное имя должно
выглядеть как модель Claude.

- Используйте шлюз: он отдаёт `claude-sonnet-4-5[1m]`, `claude-opus-4-5`,
  `claude-haiku-4-5` и маппит их на провайдера.
- В прямом режиме используйте имена из `client.direct`. Для DeepSeek они
  Claude-подобные, потому что DeepSeek маппит их на своей стороне.
- Для Tencent/Alibaba/OpenRouter в прямом режиме, если клиент rejects нативное
  имя, переключитесь на шлюз (`qclaude-gw.ps1`).

## `API Error: Invalid URL`

`ANTHROPIC_BASE_URL` должен содержать схему:

```text
https://api.deepseek.com/anthropic
```

а не `api.deepseek.com/anthropic`. То же для всех провайдеров.

## 404 / no route

- `POST /v1/messages` — конечный путь. Шлюз сам добавляет `/v1/messages` к
  `upstream`; не включайте его в `upstream`.
- Base URL OpenRouter — `https://openrouter.ai/api`, не
  `https://openrouter.ai/api/v1`.
- Base URL Alibaba заканчивается на `/apps/anthropic`, без лишнего `/v1`.
- Смотрите `upstream` в `/health`.

## 429 / rate limit

- Провайдер ограничивает частоту. Подождите.
- Шлюз уже повторяет 429 с backoff (`limits.maxRetries`).
- Уменьшите фоновые вызовы: `CLAUDE_CODE_EFFORT_LEVEL`, контекст, число
  параллельных субагентов.
- Дневной бюджет шлюза тоже возвращает 429:
  ```json
  { "limits": { "dailyBudget": 0 } }
  ```

## 5xx / timeout

- Шлюз повторяет 408/429/500/502/503/504.
- `limits.timeoutMs` по умолчанию 10 минут. Очень длинные ходы могут его
  превысить; увеличивайте осознанно.
- Проверьте статус провайдера и поле `err` в логе.
- При перегрузке смените провайдера или модель.

## Стриминг обрывается, инструменты не работают

- Некоторые провайдеры поддерживают не все SSE-события Anthropic. Смотрите
  таблицу совместимости.
- `documents: native` ставьте только если провайдер принимает блоки `document`.
  Иначе `none` (вложение заменяется заглушкой).
- Инструменты требуют поддержки `tool_use`. Это зависит от провайдера.
- Проверьте простым запросом:
  ```powershell
  claude -p "Reply with exactly OK" --output-format text
  ```

## Изображения

- DeepSeek `deepseek-v4-pro` молча игнорирует изображения. Шлюз перенаправляет
  запрос на `deepseek-flash`, если это возможно; ищите `images: heavy->main` в
  `applied`.
- Если vision-модели нет, в логе будет
  `images: no vision-capable model configured`. Запрос пройдёт, но модель может
  галлюцинировать.
- Для Tencent/Alibaba проверьте, поддерживает ли выбранная модель картинки.
- Проверьте на скриншоте с известным числом.

## PDF и документы

- DeepSeek принимает PDF только через Files API. Инлайновые base64 `document`
  шлюз загружает сам.
- Документы внутри `tool_result` поднимаются наверх для DeepSeek; иначе модель
  отвечает `NO-DOCUMENT`.
- Загруженные файлы кэшируются в `gateway/logs/files.json` по SHA-256.
- При `documents: "none"` вложение заменяется заглушкой; модель PDF не прочитает.
- При `documents: "native"` блок передаётся как есть (OpenRouter поддерживает
  PDF).
- Парсинг Files API платный; проверяйте консоль.

## Claude Desktop

Claude Desktop — самая сложная часть. Он часто игнорирует:

- переменные окружения процесса;
- `C:\Program Files\ClaudeCode\managed-settings.json` (путь CLI);
- `HKLM\SOFTWARE\Policies\ClaudeCode` (в логе
  `[managedConfig] type: 'none'`).

Варианты от мягкого к жёсткому:

1. **CC Switch** — сторонний локальный роутер с панелью Desktop. Держит свой
   шлюз на `127.0.0.1:15721`.
2. **Экспериментальная политика** — установщик с `-ConfigureDesktop` или:
   ```powershell
   .\desktop\apply-desktop-policy.ps1   # администратор
   ```
   Перезапустите Desktop и проверьте, применяются ли настройки.
3. **MITM** — самый надёжный:
   ```powershell
   .\desktop\mitm\setup-mitm.ps1        # администратор
   ```
   Создаёт локальный CA, доверяет ему, выпускает сертификат для
   `api.anthropic.com`, правит `hosts` и пишет PFX для TLS-слушателя шлюза.
   Затем запустите шлюз с `GATEWAY_TLS_PFX` (helper `gateway\gw-env.ps1` находит
   PFX сам).

Откат:

```powershell
.\desktop\mitm\teardown-mitm.ps1      # администратор
.\desktop\revert-all.ps1              # политики и managed settings
```

Не совмещайте MITM с VPN или корпоративной TLS-инспекцией без понимания цепочки
сертификатов.

## Порт 8788 занят

```powershell
Get-NetTCPConnection -LocalPort 8788 -State Listen
.\gateway\start.ps1 -Stop
```

Или измените порт в `gateway/config.json` и в `~/.claude/settings.json`
(`ANTHROPIC_BASE_URL`).

Шлюз пишет `gateway/logs/gateway.pid`. `start.ps1 -Stop` использует его, затем
падает на поиск по порту.

## Node.js и npm

- Claude Code нужен Node.js 22+ (`node --version`).
- Если `npm install -g` падает с `EACCES`/`EPERM`, установщик повторяет
  установку в `%LOCALAPPDATA%\QClaudeCode\npm` и добавляет путь в PATH.
- Если `claude` всё равно не найден, откройте новый терминал или выполните:
  ```powershell
  $env:Path += ";$env:LOCALAPPDATA\QClaudeCode\npm"
  ```
- `npm.ps1` может блокироваться политикой; используйте `npm.cmd`.
- Переносимый Node лежит в `%LOCALAPPDATA%\QClaudeCode\tools\node`.

## winget / установка Claude Desktop

- `winget` входит в App Installer. Обновите его из Microsoft Store.
- ID пакета: `Anthropic.Claude`.
- Если winget не работает, установите вручную с <https://claude.ai/download> и
  запустите установщик с `-SkipClaudeDesktop`.
- Для основного шлюза администратор не нужен; некоторые winget/MSI пути могут
  запросить UAC.

## UAC и `-ConfigureDesktop`

`-ConfigureDesktop` пишет в `C:\Program Files` и `HKLM`, поэтому нужен
администратор. Установщик запускает elevated PowerShell и ждёт. Если отменить
UAC, установка продолжится, пропустится только политика Desktop.

## Политика выполнения

Если `.\install.ps1` блокируется:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Не меняйте политику выполнения для всей машины из-за этого проекта.

## Логи и дампы

```powershell
Get-Content gateway\logs\requests.jsonl -Tail 20
```

Для ошибок запуска и необработанных исключений запустите шлюз в форграунде:

```powershell
.\gateway\start.ps1 -Stop
.\gateway\start.ps1
```

Временный полный дамп:

```powershell
$env:GATEWAY_DUMP = '1'
.\gateway\start.ps1
```

Дамп содержит промпты, вывод инструментов и, возможно, данные файлов. Удалите
`logs\last-request.json` и снимите `GATEWAY_DUMP`.

## Сброс

Мягкий сброс (приложения и ключи остаются):

```powershell
.\gateway\start.ps1 -Stop
Remove-Item "$env:LOCALAPPDATA\QClaudeCode\gateway\logs" -Recurse -Force
```

Полный сброс:

```powershell
.\uninstall.ps1
```

Переустановка с тем же или новым провайдером:

```powershell
.\install.ps1 -Provider openrouter
```

## Если ничего не помогло

Соберите:

- вывод `GET /health`;
- последние 5 строк `requests.jsonl`;
- точный текст ошибки Claude Code;
- провайдера, ID модели и эндпоинт (без ключа);
- версии Node.js, Claude Code и Windows.

Откройте issue в репозитории. Удалите ключи, токены, промпты и личные пути.
