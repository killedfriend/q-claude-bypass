# macOS

> **Учебный некоммерческий проект.** Это MVP-поддержка macOS. Скрипты
> проверяются в GitHub Actions на `macos-latest`, но живой Claude Desktop,
> доверие сертификату и GUI на реальном Mac пока не проверялись. Используйте на
> свой риск.

## Что поддерживается

- Gateway на Node.js (уже кроссплатформенный).
- `qclaude` и `qclaude-gw` для Claude Code.
- Автозапуск через LaunchAgent `com.qclaude.gateway`.
- MITM для Claude Desktop: локальный CA через `openssl`, доверие через
  `security`, `hosts`, `pfctl` redirect `443 → 8443`.
- Сборка `.zip` и `.pkg` на macOS-раннере GitHub Actions.

## Требования

- macOS 12+ (Apple Silicon или Intel).
- Node.js 22+.
- Claude Code (`npm install -g @anthropic-ai/claude-code`).
- Claude Desktop — по желанию; установщик попробует `brew install --cask claude`.
- Administrator password для MITM: `hosts`, System keychain, `pfctl`.
- Для `.pkg` — Xcode Command Line Tools не нужны пользователю, но нужны сборщику.

## Установка из ZIP (рекомендуется)

Скачайте `QClaudeCode-<version>-macos.zip` из Releases и распакуйте.

В Finder:

1. Откройте папку `QClaudeCode-<version>`.
2. Правый клик по `install.command` → **Open**. Если macOS ругается на
   неизвестного разработчика, повторите правый клик → Open.
3. Выберите провайдера и вставьте API-ключ.
4. Подтвердите запрос пароля администратора для MITM.

Через Terminal:

```bash
cd ~/Downloads/QClaudeCode-*
bash macos/install.sh
```

Полезные флаги:

```bash
bash macos/install.sh --provider deepseek
bash macos/install.sh --provider homyak
bash macos/install.sh --provider openrouter --no-mitm
bash macos/install.sh --skip-desktop
bash macos/install.sh --install-dir "$HOME/QClaude"
```

Доступны те же пресеты, что и в Windows: DeepSeek, Tencent, Alibaba,
OpenRouter и Homyak API.

## Установка из PKG

`.pkg` — неподписанный пакет. Он ставит runtime в `/usr/local/share/qclaude` и
команду `qclaude-setup`.

1. Правый клик по `.pkg` → **Open** (Gatekeeper).
2. После установки откройте Terminal и выполните:

```bash
qclaude-setup
```

`qclaude-setup` запускает тот же пользовательский установщик: копирует файлы в
`~/Library/Application Support/QClaudeCode`, настраивает ключ, LaunchAgent и,
если не указан `--no-mitm`, MITM.

Пакет не подписан и не notarized. Для нормальной поставки нужен Apple Developer
account, подпись и notarization.

## Что установщик меняет

| Путь | Назначение |
|---|---|
| `~/Library/Application Support/QClaudeCode` | Gateway, launchers, docs, env |
| `~/Library/Application Support/QClaudeCode/env` | API-ключ, права `600` |
| `~/.zshrc` | Добавляет `.../QClaudeCode/bin` в PATH |
| `~/Library/LaunchAgents/com.qclaude.gateway.plist` | Автозапуск gateway |
| `~/.claude/settings.json` | `ANTHROPIC_*` для Claude Code |
| `~/.claude.json` | `hasCompletedOnboarding: true` |
| `/etc/hosts` | `127.0.0.1 api.anthropic.com` (только MITM) |
| System keychain | CA `QClaude Local CA` (только MITM) |
| `/etc/pf.conf`, `/etc/pf.anchors/com.qclaude` | Redirect 443 → 8443 |
| `/Library/LaunchDaemons/com.qclaude.pf.plist` | Восстановление pf при загрузке |

## MITM и pfctl

macOS не разрешает обычному пользователю слушать порт 443. Поэтому:

```text
Claude Desktop → https://api.anthropic.com:443
      │ hosts → 127.0.0.1
      ▼
pfctl redirect 443 → 127.0.0.1:8443
      ▼
QClaude gateway TLS (user, 8443) → DeepSeek / Tencent / Alibaba / OpenRouter
```

Скрипт `macos/mitm/setup.sh`:

1. создаёт CA и сертификат `api.anthropic.com` через OpenSSL;
2. добавляет CA в System keychain через `security`;
3. прописывает `127.0.0.1 api.anthropic.com` в `/etc/hosts`;
4. создаёт `/etc/pf.anchors/com.qclaude` и добавляет ссылки в `/etc/pf.conf`;
5. ставит LaunchDaemon `com.qclaude.pf`, который поднимает pf при загрузке;
6. запускает `pfctl`.

Проверка:

```bash
curl -k https://api.anthropic.com/health
# должен вернуть health JSON gateway
```

Если MITM не нужен:

```bash
bash macos/install.sh --no-mitm
```

Отключить MITM позже:

```bash
sudo env QCLAUDE_HOME="$HOME/Library/Application Support/QClaudeCode" \
  "$HOME/Library/Application Support/QClaudeCode/macos/mitm/teardown.sh"
```

## Команды

```bash
qclaude-gw                 # Claude Code через gateway
qclaude-gw -p "..."        # headless
qclaude                    # напрямую к провайдеру

~/"Library/Application Support/QClaudeCode/gateway/start.sh" --background
~/"Library/Application Support/QClaudeCode/gateway/start.sh" --stop
curl http://127.0.0.1:8788/health
```

После установки откройте новый Terminal или выполните:

```bash
source ~/.zshrc
```

## Удаление

```bash
bash ~/"Library/Application Support/QClaudeCode/macos/uninstall.sh"
```

Опции:

```bash
--keep-settings       не трогать ~/.claude/settings.json
--no-mitm-cleanup     оставить hosts, CA и pf
--remove-key          удалить файл с ключом
```

Если MITM teardown отменён, установочный каталог сохраняется, чтобы можно было
повторить очистку.

## Ограничения

- Claude Desktop GUI и системное доверие сертификату не проверены на живом Mac.
- `pfctl` redirect на loopback может вести себя по-разному на версиях macOS;
  проверяйте `curl -k https://api.anthropic.com/health`.
- `.pkg` не подписан; Gatekeeper предупредит.
- Корпоративные VPN, TLS-inspection и managed Mac могут конфликтовать с MITM.
- Модели, цены и API провайдеров меняются; проверяйте документацию провайдера.
- Проект не связан с Anthropic, DeepSeek, Tencent, Alibaba или OpenRouter.

## Диагностика

```bash
# gateway
curl -v http://127.0.0.1:8788/health
tail -n 50 ~/"Library/Application Support/QClaudeCode/gateway/logs/launchd.err.log"

# LaunchAgent
launchctl print "gui/$(id -u)/com.qclaude.gateway"

# hosts / cert / pf
grep qclaude-mitm /etc/hosts
security find-certificate -c "QClaude Local CA" /Library/Keychains/System.keychain
sudo pfctl -s nat | grep 8443
sudo pfctl -a com.qclaude -sr

# gateway TLS
lsof -nP -iTCP:8443 -sTCP:LISTEN
```

Если после перезагрузки не работает MITM, проверьте LaunchDaemon:

```bash
sudo launchctl print system/com.qclaude.pf
sudo pfctl -E
sudo pfctl -f /etc/pf.conf
```
