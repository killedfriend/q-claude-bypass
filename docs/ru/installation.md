# Установка

> **Учебный некоммерческий проект.** Репозиторий создан для демонстрации и
> обучения. Он не связан с Anthropic, DeepSeek, Tencent, Alibaba или OpenRouter.
> Не используйте его коммерчески или в нарушение условий провайдеров.
> Ответственность за использование лежит на вас.

## Требования

- Windows 10 или 11 (x64).
- PowerShell 5.1 или новее.
- Доступ в интернет к GitHub, npm, nodejs.org и вашему провайдеру.
- API-ключ DeepSeek, Tencent Cloud, Alibaba Cloud Model Studio или OpenRouter.
- Желательно `winget` (App Installer) для Claude Desktop. Если его нет,
  установщик предложит ссылку для ручной установки.

Node.js, Claude Code и Claude Desktop заранее устанавливать не нужно.

## Установка одной командой

Откройте обычный PowerShell (права администратора для основной установки не
нужны) и выполните:

```powershell
irm https://github.com/killedfriend/q-claude-bypass/releases/latest/download/install.ps1 | iex
```

Если политика выполнения блокирует команду:

```powershell
powershell -ExecutionPolicy Bypass -Command "irm https://github.com/killedfriend/q-claude-bypass/releases/latest/download/install.ps1 | iex"
```

Установщик спросит:

1. провайдера (DeepSeek, Tencent, Alibaba, OpenRouter);
2. API-ключ (ввод скрыт).

Ключ сохраняется в пользовательскую переменную окружения и не попадает в
репозиторий.

### Неинтерактивная установка

```powershell
$env:QCLAUDE_PROVIDER = 'alibaba'
$env:QCLAUDE_API_KEY  = 'sk-...'
irm https://github.com/killedfriend/q-claude-bypass/releases/latest/download/install.ps1 | iex
```

Не передавайте ключ прямо в командной строке: он может остаться в истории
PowerShell или в списке процессов. Лучше использовать скрытый ввод.

### Параметры установщика

Скачайте `install.ps1` и запустите файлом, чтобы передать параметры:

```powershell
.\install.ps1 -Provider openrouter -InstallDir D:\Tools\QClaude
```

| Параметр | Значение |
|---|---|
| `-Provider` | `deepseek`, `tencent`, `alibaba`, `openrouter` |
| `-ApiKey` | API-ключ; если не указан, установщик спросит |
| `-InstallDir` | Каталог установки, по умолчанию `%LOCALAPPDATA%\QClaudeCode` |
| `-ClaudeHome` | Каталог настроек Claude, по умолчанию `%USERPROFILE%\.claude` |
| `-SourceDir` | Установить из локальной копии репозитория вместо ZIP |
| `-Repo` | GitHub-репозиторий для загрузки релиза |
| `-Version` | Версия релиза для загрузки |
| `-SkipNode` | Не проверять и не устанавливать Node.js |
| `-SkipClaudeCode` | Не устанавливать Claude Code |
| `-SkipClaudeDesktop` | Не устанавливать Claude Desktop |
| `-SkipAutostart` | Не регистрировать автозапуск и не запускать шлюз |
| `-SkipSmokeTest` | Не отправлять проверочный запрос |
| `-NoPersistKey` | Хранить ключ только в текущем процессе (автозапуск его не увидит) |
| `-NoStart` | Не запускать шлюз после установки |
| `-ConfigureDesktop` | Применить экспериментальную политику Desktop (нужен UAC) |

## Что меняет установщик

| Расположение | Изменение |
|---|---|
| `%LOCALAPPDATA%\QClaudeCode` | Шлюз, лаунчеры, документация, примеры |
| `%LOCALAPPDATA%\QClaudeCode\bin` | Обёртки `qclaude` и `qclaude-gw`, добавляются в пользовательский PATH |
| `%LOCALAPPDATA%\QClaudeCode\tools\node` | Переносимый Node.js, только если Node.js не было и winget не сработал |
| `%USERPROFILE%\.claude\settings.json` | Добавляет переменные шлюза `ANTHROPIC_*`, остальные настройки сохраняются |
| `%USERPROFILE%\.claude.json` | Устанавливает `hasCompletedOnboarding: true` |
| `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` | Запись автозапуска `QClaudeGateway` |
| Пользовательские переменные | Переменная ключа, например `DASHSCOPE_API_KEY` |
| Опционально, с `-ConfigureDesktop` | `C:\Program Files\ClaudeCode\managed-settings.json` и `HKLM\SOFTWARE\Policies\ClaudeCode` |
| `%LOCALAPPDATA%\QClaudeCode\gateway\logs` | Рабочие логи |

Бинарники Claude Code и Claude Desktop не изменяются.

## Проверка

Откройте новый терминал, чтобы обновились PATH и пользовательские переменные.

```powershell
qclaude-gw
```

В другом терминале:

```powershell
Invoke-RestMethod http://127.0.0.1:8788/health
```

Ожидаемые поля: `"ok": true`, выбранный `provider`, `routes`,
`keyConfigured: true`.

Дешёвый проверочный запрос:

```powershell
$body = @{
  model = 'claude-haiku-4-5'
  max_tokens = 32
  messages = @(@{ role = 'user'; content = 'Reply with exactly: OK' })
} | ConvertTo-Json -Depth 5

Invoke-RestMethod http://127.0.0.1:8788/v1/messages -Method Post `
  -Headers @{ 'x-api-key' = 'local-gateway'; 'anthropic-version' = '2023-06-01' } `
  -ContentType 'application/json' -Body $body
```

Расход:

```powershell
node "$env:LOCALAPPDATA\QClaudeCode\gateway\report.mjs"
```

## Ручная установка

Если хотите сначала изучить или изменить исходники:

```powershell
git clone https://github.com/killedfriend/q-claude-bypass.git
cd q-claude-bypass

# 1. Node.js 22+
node --version

# 2. Claude Code
npm install -g @anthropic-ai/claude-code

# 3. Ключ провайдера (пример: DeepSeek)
[Environment]::SetEnvironmentVariable('DEEPSEEK_API_KEY', 'sk-...', 'User')

# 4. Выбор провайдера
#    отредактируйте gateway/config.json -> "provider": "deepseek"
#    или задайте переменную для текущего процесса:
$env:GATEWAY_PROVIDER = 'deepseek'

# 5. Проверка ключа
.\test-connection.ps1

# 6. Запуск
.\qclaude-gw.ps1
```

Автозапуск вручную:

```powershell
$install = (Resolve-Path .).Path
$cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$install\gateway\autostart.ps1`""
New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' `
  -Name 'QClaudeGateway' -Value $cmd -PropertyType String -Force
```

Есть и вариант с планировщиком:

```powershell
.\desktop\install-autostart.ps1          # нужен администратор
.\desktop\install-autostart.ps1 -Remove
```

## Обновление

Запустите установщик снова. Он остановит старый шлюз, заменит рабочие файлы,
сохранит `gateway/logs` и перезапишет `gateway/config.json` выбранным
провайдером. Если вы меняли маршруты или лимиты, сделайте резервную копию:

```powershell
copy "$env:LOCALAPPDATA\QClaudeCode\gateway\config.json" "$env:LOCALAPPDATA\QClaudeCode\gateway\config.backup.json"
```

Пресеты провайдеров заменяются новой версией. Свои пресеты храните в отдельном
файле `.local.json` и указывайте его в `provider`.

## Удаление

```powershell
irm https://github.com/killedfriend/q-claude-bypass/releases/latest/download/uninstall.ps1 | iex
```

Удаляются:

- запись автозапуска `QClaudeGateway`;
- запущенный процесс шлюза;
- переменные `ANTHROPIC_*`, добавленные в `~/.claude/settings.json`;
- каталог установки.

Claude Code, Claude Desktop и API-ключи по умолчанию остаются. Дополнительные
ключи:

```powershell
.\uninstall.ps1 -RemoveApiKey -RemoveClaudeCode -RemoveClaudeDesktop
```

`-KeepSettings` оставляет настройки Claude нетронутыми.

## Claude Desktop

Установщик ставит Desktop, но не перенаправляет его трафик. Claude Desktop часто
игнорирует переменные окружения и managed-settings. См.
[диагностику](troubleshooting.md#claude-desktop) и корневой README: есть три
варианта — CC Switch, экспериментальная политика или MITM.

## Дальше

- [Провайдеры](providers.md)
- [Конфигурация](configuration.md)
- [Диагностика](troubleshooting.md)
