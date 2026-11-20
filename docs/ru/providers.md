# Провайдеры

> **Учебный некоммерческий проект.** Названия и эндпоинты провайдеров
> используются только для описания совместимости. Проект с ними не связан.
> Перед использованием проверьте актуальную документацию, тарифы и условия.

Все пять пресетов работают через Anthropic-совместимый эндпоинт. Шлюз
нормализует имена моделей, аутентификацию и неподдерживаемые блоки, поэтому
Claude Code всегда видит публичные имена `claude-*`.

## Сводка

| Провайдер | Пресет | Base URL | Аутентификация | Основная модель |
|---|---|---|---|---|
| DeepSeek | `gateway/providers/deepseek.json` | `https://api.deepseek.com/anthropic` | `Authorization: Bearer` + `DEEPSEEK_API_KEY` | `deepseek-flash[1m]` |
| Tencent Hunyuan | `gateway/providers/tencent.json` | `https://api.hunyuan.cloud.tencent.com/anthropic` | `x-api-key` + `TENCENT_API_KEY` | `hunyuan-2.0-instruct-20251111` |
| Alibaba Bailian | `gateway/providers/alibaba.json` | `https://dashscope.aliyuncs.com/apps/anthropic` | `Authorization: Bearer` + `DASHSCOPE_API_KEY` | `qwen3.7-plus` |
| OpenRouter | `gateway/providers/openrouter.json` | `https://openrouter.ai/api` | `Authorization: Bearer` + `OPENROUTER_API_KEY` | `anthropic/claude-sonnet-4.5` |
| Хомяк API | `gateway/providers/homyak.json` | `https://api.homyakstudio.ru` | `Authorization: Bearer` + `HOMYAK_API_KEY` | `homyak-flash` |

ID моделей приведены как примеры и со временем меняются.

> **Статус проверки.** DeepSeek проверен живыми запросами 2026-11-19. Пресеты
> Tencent, Alibaba, OpenRouter и Хомяк API собраны по официальной документации
> и в этом репозитории живьём не проверялись. Сверьте ID моделей, эндпоинт и
> заголовок аутентификации для своего аккаунта.

## DeepSeek

Ключ: <https://platform.deepseek.com/api_keys>.

```powershell
[Environment]::SetEnvironmentVariable('DEEPSEEK_API_KEY', 'sk-...', 'User')
```

Прямые настройки Claude Code (`~/.claude/settings.json`):

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://api.deepseek.com/anthropic",
    "ANTHROPIC_AUTH_TOKEN": "sk-...",
    "ANTHROPIC_API_KEY": "",
    "ANTHROPIC_MODEL": "claude-sonnet-4-5[1m]",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "claude-opus-4-5",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "claude-sonnet-4-5[1m]",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "claude-haiku-4-5",
    "CLAUDE_CODE_SUBAGENT_MODEL": "claude-sonnet-4-5"
  }
}
```

Почему имена выглядят как модели Claude: Claude Code проверяет имя модели на
клиенте. DeepSeek сопоставляет `claude-opus*` с `deepseek-v4-pro`, остальные
`claude*` — с `deepseek-flash`; суффикс `[1m]` включает контекст 1M. Шлюз
делает то же самое явно, поэтому публичные имена остаются стабильными.

Особенности DeepSeek в шлюзе:

- **Изображения.** `deepseek-v4-pro` молча игнорирует картинки. Запросы с
  изображениями перенаправляются на `deepseek-flash`, если есть vision-маршрут.
- **PDF.** Инлайновые `document` загружаются через Files API
  (`rich_layout_recognition`) и кэшируются по SHA-256. Документы внутри
  `tool_result` поднимаются на верхний уровень сообщения.
- **Веб-поиск.** `usage.server_tool_use` оплачивается за вызов и добавляется к
  стоимости запроса.
- **Пиковые часы.** Будни 09:00–12:00 и 14:00–18:00 по Пекину. Праздники КНР
  не учитываются.

## Tencent Hunyuan

Ключ создаётся в консоли Hunyuan: <https://console.cloud.tencent.com/hunyuan>.

Anthropic-совместимый эндпоинт:

```text
https://api.hunyuan.cloud.tencent.com/anthropic
```

Текущие модели в документации: `hunyuan-2.0-thinking-20251109` и
`hunyuan-2.0-instruct-20251111`. В пресете шлюза ключ отправляется как
`x-api-key`. В руководстве Tencent для Claude Code используется
`ANTHROPIC_AUTH_TOKEN`; оба варианта описаны провайдером.

Прямые настройки:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://api.hunyuan.cloud.tencent.com/anthropic",
    "ANTHROPIC_AUTH_TOKEN": "your-tencent-api-key",
    "ANTHROPIC_MODEL": "hunyuan-2.0-instruct-20251111",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "hunyuan-2.0-thinking-20251109",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "hunyuan-2.0-instruct-20251111",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "hunyuan-2.0-instruct-20251111",
    "CLAUDE_CODE_SUBAGENT_MODEL": "hunyuan-2.0-instruct-20251111"
  }
}
```

### Tencent TokenHub / Coding Plan

Tencent переводит новые модели в TokenHub. Эндпоинт Coding Plan:

```text
https://api.lkeap.cloud.tencent.com/coding/anthropic
```

Используйте ключ Coding Plan и имя модели из тарифа (например, `glm-5`).
Скопируйте `gateway/providers/tencent.json` в локальный пресет, измените
`upstream`, `models`, `client` и переменную ключа, затем укажите `provider` в
`gateway/config.json`.

## Alibaba Cloud Bailian (Qwen)

Ключ: <https://bailian.console.aliyun.com/>.

Актуальные Anthropic-совместимые эндпоинты:

| Тариф | Base URL |
|---|---|
| Оплата по запросам | `https://dashscope.aliyuncs.com/apps/anthropic` |
| Coding Plan | `https://coding.dashscope.aliyuncs.com/apps/anthropic` |
| Token Plan | `https://token-plan.cn-beijing.maas.aliyuncs.com/apps/anthropic` |

Старый эндпоинт `https://dashscope.aliyuncs.com/api/v2/apps/claude-code-proxy`
устарел и обслуживает только снятые с поддержки модели.

Прямые настройки:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://dashscope.aliyuncs.com/apps/anthropic",
    "ANTHROPIC_AUTH_TOKEN": "sk-...",
    "ANTHROPIC_MODEL": "qwen3.7-plus",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "qwen3.7-max",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "qwen3.7-plus",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "qwen3.6-flash",
    "CLAUDE_CODE_SUBAGENT_MODEL": "qwen3.7-plus"
  }
}
```

Тип ключа должен соответствовать эндпоинту. Ключ оплаты по запросам (`sk-`) не
подойдёт к Coding Plan или Token Plan.

Пресет шлюза: `qwen3.7-plus` (main), `qwen3.7-max` (heavy),
`qwen3.6-flash` (cheap).

## OpenRouter

Ключ: <https://openrouter.ai/keys>.

OpenRouter предоставляет Anthropic Messages эндпоинт:

```text
https://openrouter.ai/api/v1/messages
```

Claude Code добавляет `/v1/messages` к `ANTHROPIC_BASE_URL`, поэтому базовый URL
должен быть `https://openrouter.ai/api` (не `.../api/v1`).

Прямые настройки:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://openrouter.ai/api",
    "ANTHROPIC_AUTH_TOKEN": "sk-or-v1-...",
    "ANTHROPIC_MODEL": "anthropic/claude-sonnet-4.5",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "anthropic/claude-opus-4.5",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "anthropic/claude-sonnet-4.5",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "anthropic/claude-haiku-4.5",
    "CLAUDE_CODE_SUBAGENT_MODEL": "anthropic/claude-sonnet-4.5"
  }
}
```

Пресет шлюза также отправляет заголовки `HTTP-Referer` и `X-Title`, которые
OpenRouter использует для атрибуции. Замените URL репозитория в
`gateway/providers/openrouter.json`, если публикуете свой форк.

OpenRouter возвращает `usage.cost`. Шлюз сохраняет точное значение, а не
оценивает по таблице; таблица используется только как запасной вариант.

## Хомяк API (homyakstudio.ru)

Российский сервис с Anthropic-совместимым эндпоинтом к DeepSeek. Подходит,
если нет иностранной карты: кошелёк и списание — в рублях.

- Регистрация, пополнение и создание ключа:
  <https://homyakstudio.ru/?utm_source=github>.
- Оплата: карта РФ, СБП, MirPay и SberPay, пополнение от 500 ₽; для ИП и ООО —
  счёт от 1 000 ₽.
- Anthropic base URL: `https://api.homyakstudio.ru` (Claude Code добавляет
  `/v1/messages`).
- Ключ `sk-hmk-…` отправляется как `Authorization: Bearer`.

Модель одна — `homyak-flash` (DeepSeek V4.1 Flash): 1M контекста, 384K ответа,
изображения, инструменты. Цены в рублях за 1M токенов:

| Тариф | Вход | Кеш | Выход |
|---|---|---|---|
| Пик (будни 09:00–12:00 и 14:00–18:00 по Пекину) | 39,00 ₽ | 0,78 ₽ | 156,00 ₽ |
| Не пик | 19,50 ₽ | 0,39 ₽ | 78,00 ₽ |

Прямые настройки:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://api.homyakstudio.ru",
    "ANTHROPIC_AUTH_TOKEN": "sk-hmk-...",
    "ANTHROPIC_API_KEY": "",
    "ANTHROPIC_MODEL": "homyak-flash",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "homyak-flash",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "homyak-flash",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "homyak-flash",
    "CLAUDE_CODE_SUBAGENT_MODEL": "homyak-flash"
  }
}
```

В пресете шлюза все три роли (`main`, `heavy`, `cheap`) указывают на
`homyak-flash`, а `currency` — `RUB`: расход в `report.mjs` и дневной бюджет
считаются в рублях по тарифу пик/непик. PDF не поддерживается — шлюз убирает
блоки `document` и пишет причину в `notes`.

## Переключение провайдера

Отредактируйте `gateway/config.json`:

```json
{ "provider": "alibaba" }
```

Или задайте только для процесса:

```powershell
$env:GATEWAY_PROVIDER = 'openrouter'
.\gateway\start.ps1
```

После изменения конфигурации перезапустите шлюз. Работающие запросы конфиг не
перечитывают.

Установщик записывает провайдера в `gateway/config.json` и сохраняет ключ в
соответствующую пользовательскую переменную.

## Свой провайдер

1. Скопируйте `gateway/providers/openrouter.json` в
   `gateway/providers/my-provider.json`.
2. Заполните `name`, `docs`, `upstream`, `currency`, `auth`, `models`, `vision`,
   `documents`, `pricing` и `client`.
3. Установите `"provider": "my-provider"` в `gateway/config.json`.
4. Положите ключ в переменную из `auth.env`.
5. Перезапустите шлюз и проверьте `GET /health`.

ID провайдера должен соответствовать `[a-z0-9][a-z0-9_-]*`. Файлы загружаются
из `gateway/providers/`.

Минимальный пример:

```json
{
  "name": "My Provider",
  "upstream": "https://api.example.com/anthropic",
  "currency": "USD",
  "auth": {
    "mode": "gateway",
    "header": "authorization",
    "scheme": "Bearer ",
    "env": "MY_PROVIDER_API_KEY"
  },
  "models": {
    "main": "model-main",
    "heavy": "model-heavy",
    "cheap": "model-cheap"
  },
  "vision": ["model-main"],
  "documents": "native",
  "cheapProfile": { "maxTokens": 4096 },
  "pricing": {},
  "client": {
    "direct": { "model": "model-main", "opus": "model-heavy", "sonnet": "model-main", "haiku": "model-cheap", "subagent": "model-main" },
    "gateway": { "model": "claude-sonnet-4-5[1m]", "opus": "claude-opus-4-5", "sonnet": "claude-sonnet-4-5[1m]", "haiku": "claude-haiku-4-5", "subagent": "claude-sonnet-4-5" }
  }
}
```

## Примеры

Прямые настройки для всех провайдеров:

- `examples/claude-settings/deepseek.settings.json`
- `examples/claude-settings/tencent.settings.json`
- `examples/claude-settings/alibaba.settings.json`
- `examples/claude-settings/openrouter.settings.json`
- `examples/claude-settings/homyak.settings.json`

Это шаблоны: замените `<YOUR_..._KEY>` и объедините блок `env` с существующим
`~/.claude/settings.json`. Не перезаписывайте остальные настройки.

## Совместимость

| Возможность | DeepSeek | Tencent | Alibaba | OpenRouter | Хомяк API |
|---|---|---|---|---|---|
| Стриминг | да | да | да | да | да |
| Инструменты | да | да | да | да | да |
| Изображения | только flash; шлюз перенаправляет | зависит от модели | зависит от модели | зависит от модели | да |
| PDF | Files API | не поддерживается | не поддерживается | нативно | не поддерживается |
| Веб-поиск на стороне провайдера | оплачивается и логируется | зависит от модели | зависит от модели | зависит от модели | нет |
| Точная стоимость из ответа | нет | нет | нет | да (`usage.cost`) | нет |

Возможности провайдеров меняются. Если запрос падает, смотрите
`gateway/logs/requests.jsonl`, поле `notes` и заголовок `x-gateway-route`.
