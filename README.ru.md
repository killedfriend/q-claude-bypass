# QClaude Code

[![Release](https://img.shields.io/github/v/release/killedfriend/q-claude-bypass?label=release)](https://github.com/killedfriend/q-claude-bypass/releases)
[![CI](https://github.com/killedfriend/q-claude-bypass/actions/workflows/ci.yml/badge.svg)](https://github.com/killedfriend/q-claude-bypass/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[English](README.en.md) · [中文](README.zh-CN.md) · **Русский**

> **Учебный некоммерческий проект.** Этот репозиторий создан исключительно для
> демонстрации и обучения. Он не связан с Anthropic, DeepSeek, Tencent, Alibaba
> или OpenRouter и не одобрен ими. Проект не предназначен для коммерческого
> использования, перепродажи, обхода платного доступа или нарушения условий
> обслуживания провайдеров. Используйте его на свой риск; ответственность за
> соблюдение применимых условий и законов лежит на вас.

QClaude Code запускает настоящий Claude Code и Claude Desktop с моделями
сторонних провайдеров через официальный механизм `ANTHROPIC_BASE_URL`. Между
клиентом и провайдером стоит небольшой локальный шлюз: он маршрутизирует модели,
ведёт учёт токенов и денег, повторяет запросы при ошибках и убирает блоки,
которые провайдер не принимает.

Проект вырос из практического эксперимента: проверить, насколько далеко можно
уйти от Anthropic API, не форкая Claude Code и не патча его бинарники.

## Что внутри

- **Настоящий Claude Code.** Никаких форков и модификаций клиента. Только
  переменные окружения и локальный HTTP-шлюз.
- **Пять готовых провайдеров:** DeepSeek, Tencent Hunyuan, Alibaba Cloud
  Bailian (Qwen), OpenRouter, Хомяк API (homyakstudio.ru). Добавить свой
  можно одним JSON-файлом.
- **Маршрутизация моделей.** `opus` → тяжёлая модель, `haiku` и фоновые вызовы
  без инструментов → дешёвая, остальное → основная.
- **Учёт денег.** Токены, попадания в кэш, цена запроса, веб-поиск, дневной
  бюджет. Для OpenRouter берётся точная стоимость из ответа.
- **Защита от тихих ошибок.** Если модель не умеет картинки, шлюз не отдаёт ей
  изображение молча; маршрут и причина видны в логе и заголовке ответа.
- **Работа с документами.** Для DeepSeek PDF загружается через Files API и
  поднимается из `tool_result` на верхний уровень сообщения.
- **Обрезка контекста.** Старые результаты инструментов заменяются заглушками,
  чтобы длинные сессии не пересылали сотни тысяч токенов каждый ход.
- **Установщик для Windows.** Одна команда: Node.js, Claude Code, Claude
  Desktop, шлюз, автоматический MITM для Desktop, автозапуск и проверка ключа.
- **Документация на трёх языках** и примеры настроек для каждого провайдера.

## Как это работает

```text
Claude Code / Claude Desktop
        │  ANTHROPIC_BASE_URL=http://127.0.0.1:8788
        ▼
QClaude Gateway (Node.js, без зависимостей)
  ├─ выбирает провайдера из gateway/config.json
  ├─ маршрутизирует claude-opus / claude-sonnet / claude-haiku
  ├─ чистит request: cache_control, document, вложения
  ├─ считает токены, кэш, стоимость
  └─ пишет gateway/logs/requests.jsonl
        │
        ▼
DeepSeek / Tencent / Alibaba / OpenRouter / Хомяк API
```

Провайдер получает обычный запрос в формате Anthropic Messages API. Claude Code
не знает, что говорит не с Anthropic: для него это просто другой Base URL.

## Провайдеры

| Провайдер | Base URL | Переменная ключа | Примеры моделей |
|---|---|---|---|
| DeepSeek | `https://api.deepseek.com/anthropic` | `DEEPSEEK_API_KEY` | `deepseek-flash[1m]`, `deepseek-v4-pro` |
| Tencent Hunyuan | `https://api.hunyuan.cloud.tencent.com/anthropic` | `TENCENT_API_KEY` | `hunyuan-2.0-instruct-20251111`, `hunyuan-2.0-thinking-20251109` |
| Alibaba Bailian | `https://dashscope.aliyuncs.com/apps/anthropic` | `DASHSCOPE_API_KEY` | `qwen3.7-plus`, `qwen3.7-max`, `qwen3.6-flash` |
| OpenRouter | `https://openrouter.ai/api` | `OPENROUTER_API_KEY` | `anthropic/claude-sonnet-4.5`, `anthropic/claude-opus-4.5`, `anthropic/claude-haiku-4.5` |
| Хомяк API | `https://api.homyakstudio.ru` | `HOMYAK_API_KEY` | `homyak-flash` |

> **Хомяк API — оплата без иностранной карты.** Российский реселлер DeepSeek с
> Anthropic-совместимым эндпоинтом: пополнение в рублях картой РФ, СБП,
> MirPay и SberPay, от 500 ₽ (для ИП и ООО — счёт от 1 000 ₽). Регистрация и
> ключи: <https://homyakstudio.ru/?utm_source=github>. Модель одна —
> `homyak-flash` (1M контекста, 384K ответа, изображения, инструменты), расход
> шлюз считает в рублях по тарифу пик/непик.

Точные идентификаторы моделей меняются. Проверяйте их в консоли провайдера;
для OpenRouter — на странице моделей. Подробности и альтернативные тарифные
эндпоинты (Tencent TokenHub, Alibaba Coding Plan) — в
[`docs/ru/providers.md`](docs/ru/providers.md).

> **Статус проверки.** Путь DeepSeek проверен живыми запросами 2026-11-19
> (запрос, стриминг, инструменты, PDF, учёт цены) на Claude Code 2.1.326 и
> Claude Desktop 5.11492.5, Windows 11, Node 22.20. Пресеты Tencent, Alibaba,
> OpenRouter и Хомяк API собраны по официальной документации провайдеров и в
> этом репозитории живьём не проверялись. Сверьте ID моделей и заголовок
> аутентификации для своего аккаунта, прежде чем полагаться на них.

## Быстрый старт (Windows)

Требования: Windows 10/11, PowerShell 5.1+, интернет. Node.js 22+, Claude Code,
Claude Desktop и `winget` установщик подтянет сам, если их нет.

```powershell
irm https://github.com/killedfriend/q-claude-bypass/releases/latest/download/install.ps1 | iex
```

Если политика выполнения запрещает `irm | iex`:

```powershell
powershell -ExecutionPolicy Bypass -Command "irm https://github.com/killedfriend/q-claude-bypass/releases/latest/download/install.ps1 | iex"
```

Установщик:

1. проверяет Node.js 22+ и при необходимости ставит LTS (winget или переносимый
   ZIP в `%LOCALAPPDATA%\QClaudeCode\tools\node`);
2. ставит `@anthropic-ai/claude-code` через npm;
3. ставит Claude Desktop через `winget install Anthropic.Claude`;
4. копирует шлюз в `%LOCALAPPDATA%\QClaudeCode`;
5. спрашивает провайдера и API-ключ (ввод скрыт), сохраняет ключ в пользовательскую
   переменную;
6. **автоматически настраивает MITM для Claude Desktop**: локальный CA,
   сертификат `api.anthropic.com`, запись в `hosts` и PFX для TLS-слушателя
   шлюза. Этот шаг требует подтверждения UAC; отключить можно флагом `-NoMitm`;
7. прописывает шлюз в автозапуск `HKCU\...\Run\QClaudeGateway`;
8. запускает шлюз, проверяет TLS-перехват и делает один дешёвый запрос для
   проверки ключа.

Для неинтерактивной установки:

```powershell
$env:QCLAUDE_PROVIDER = 'alibaba'
$env:QCLAUDE_API_KEY  = 'sk-...'
irm https://github.com/killedfriend/q-claude-bypass/releases/latest/download/install.ps1 | iex
```

После установки откройте новый терминал:

```powershell
qclaude-gw
```

`qclaude-gw` — обёртка над `claude`, которая поднимает шлюз, если он ещё не
запущен, и передаёт все аргументы Claude Code без изменений.

Проверка и диагностика:

```powershell
Invoke-RestMethod http://127.0.0.1:8788/health
node "$env:LOCALAPPDATA\QClaudeCode\gateway\report.mjs"
Get-Content "$env:LOCALAPPDATA\QClaudeCode\gateway\logs\requests.jsonl" -Tail 5
```

Удаление:

```powershell
irm https://github.com/killedfriend/q-claude-bypass/releases/latest/download/uninstall.ps1 | iex
```

## Ручной запуск из репозитория

```powershell
git clone https://github.com/killedfriend/q-claude-bypass.git
cd q-claude-bypass

.\test-connection.ps1      # один дешёвый запрос, проверка ключа
.\qclaude.ps1              # напрямую к провайдеру
.\qclaude-gw.ps1           # через локальный шлюз
.\gateway\start.ps1        # шлюз в форграунде
.\gateway\start.ps1 -Stop  # остановить фоновый шлюз
node gateway\report.mjs    # расход по дням, моделям и провайдерам
```

Провайдер по умолчанию — DeepSeek. Переключение:

```powershell
# отредактируйте gateway/config.json -> "provider": "alibaba"
# или задайте переменную только для текущего процесса:
$env:GATEWAY_PROVIDER = 'alibaba'
.\gateway\start.ps1
```

Ключ хранится в пользовательской переменной окружения
(`DEEPSEEK_API_KEY`, `TENCENT_API_KEY`, `DASHSCOPE_API_KEY`,
`OPENROUTER_API_KEY` или `HOMYAK_API_KEY`). В репозитории ключей нет.

## Файлы

| Путь | Назначение |
|---|---|
| `install.ps1` | Установщик для Windows в одну команду |
| `install.cmd` | Обёртка для запуска установщика двойным щелчком |
| `uninstall.ps1` | Удаление автозапуска, шлюза и настроек клиента |
| `qclaude-gw.ps1` | Claude Code через локальный шлюз |
| `qclaude.ps1` | Claude Code напрямую к провайдеру |
| `env.ps1` | Выбор провайдера, ключ, модели, общие переменные |
| `test-connection.ps1` | Проверка ключа одним запросом |
| `gateway/server.mjs` | Шлюз, Node 22, без зависимостей |
| `gateway/config.json` | Общие настройки: порт, маршруты, лимиты, логи |
| `gateway/providers/*.json` | Пресеты провайдеров |
| `gateway/report.mjs` | Отчёт по расходу |
| `gateway/lib/*.mjs` | Конфиг, цены, маршрутизация, обрезка контекста |
| `desktop/` | Экспериментальная привязка Claude Desktop (политики, MITM) |
| `examples/claude-settings/` | Примеры `~/.claude/settings.json` для прямого режима |
| `docs/ru`, `docs/en`, `docs/zh` | Подробная документация |
| `scripts/build-release.ps1` | Сборка ZIP и артефактов релиза |

## Документация

- [Установка](docs/ru/installation.md) — установщик, ручная установка,
  обновление, удаление, автозапуск.
- [Провайдеры](docs/ru/providers.md) — Tencent, Alibaba, OpenRouter, DeepSeek,
  Хомяк API: ключи, эндпоинты, модели, примеры настроек.
- [Конфигурация](docs/ru/configuration.md) — шлюз, маршрутизация, цены, логи,
  бюджеты, переменные окружения.
- [Диагностика](docs/ru/troubleshooting.md) — ошибки 401/404/429, модели,
  Desktop, порт, Node.js, UAC.
- [Поддержать автора](docs/ru/support.md) — USDT-адреса, CloudTips и предупреждения.

English: [`docs/en`](docs/en) · 中文: [`docs/zh`](docs/zh).

## Claude Desktop

Установщик **по умолчанию сам настраивает MITM** для Claude Desktop: создаёт
локальный CA, добавляет его в Trusted Root, выпускает сертификат
`api.anthropic.com`, направляет этот домен в `127.0.0.1` через `hosts` и
включает TLS-слушатель шлюза на порту 443. Для этого нужен администратор и
подтверждение UAC.

Отключить автоматический MITM:

```powershell
.\install.ps1 -NoMitm
```

MITM — машинно-глобальное изменение: пока шлюз выключен, `api.anthropic.com`
на этой машине недоступен. Удаление возвращает всё назад автоматически
(`uninstall.ps1` вызывает teardown; при отмене UAC установочный каталог
сохраняется, чтобы можно было повторить откат).

Альтернативы, если MITM не подходит:

1. **CC Switch** — сторонняя утилита с локальным роутингом для Desktop.
2. **Experimental policy** — `install.ps1 -ConfigureDesktop` записывает
   managed-settings и политику реестра; на части сборок Desktop их игнорирует.

Перед MITM прочитайте [`docs/ru/troubleshooting.md`](docs/ru/troubleshooting.md)
и раздел безопасности. Ручной откат: `desktop/mitm/teardown-mitm.ps1`.

## Безопасность и ограничения

- Шлюз слушает только `127.0.0.1` и не предназначен для выхода в сеть. Не
  меняйте `listen.host` на `0.0.0.0` без аутентификации.
- API-ключи хранятся в пользовательских переменных окружения, не в репозитории.
- `gateway/logs/requests.jsonl` содержит модели, токены, имена инструментов и
  ошибки, но не тексты промптов. `GATEWAY_DUMP=1` пишет полный запрос в
  `logs/last-request.json` — не включайте на чувствительных данных.
- Проект неофициальный. Обновление Claude Code или изменение API провайдера
  может всё сломать. Откат бесплатный: не запускайте шлюз.
- Праздники КНР не учитываются в пиковых тарифах DeepSeek.
- `count_tokens` в шлюзе оценочный, индикатор контекста приблизительный.
- Изображения и PDF поддерживаются по-разному. Проверяйте `notes` в логе и
  `x-gateway-route` в ответе.
- Claude Desktop и MITM — экспериментальная часть. Не используйте на рабочих
  машинах без понимания последствий.

## Поддержать автора

Проект учебный и некоммерческий. Если он оказался полезен, можно поддержать
автора переводом **USDT**. Отправляйте **только USDT в указанной сети**:
перевод в другой сети может привести к безвозвратной потере средств.

| Сеть | Адрес |
|---|---|
| TON | `UQDi2mkFf1e0-YCwTA14bXb03rNzruouqS5xnQCG4QluLlJD` |
| Tron (TRC20) | `TRbCHiNGECmkdzRqs7Hz5684PuEwNMstK2` |
| Ethereum (ERC20) | `0x5e88d21844F45A18DFA0B687ab96f2e98FeD5303` |
| Solana | `FPiVkxdNqJENgmF3Qib8wQR6oewYjwzZjSBBLtfMY6UH` |
| BNB Smart Chain (BEP20) | `0x5e88d21844F45A18DFA0B687ab96f2e98FeD5303` |

Перед переводом проверьте адрес и сеть; для первой проверки отправьте небольшую
сумму. Донаты добровольные и не дают прав, гарантий или обязательств.

Дополнительный канал для российских карт:
[CloudTips](https://pay.cloudtips.ru/p/04b8daec). Крипта остаётся основным
каналом.

Подробнее: [docs/ru/support.md](docs/ru/support.md).

## Лицензия

MIT. См. [LICENSE](LICENSE).

Проект предоставляется «как есть», без гарантий. Авторы не несут
ответственности за расходы, потерю данных или нарушения условий провайдеров.
