# Настройка компьютера оператора для установки kiosk на планшеты

Эта инструкция для ребят, которые будут подключать готовый планшет с включённым Developer Mode и запускать установку одной командой.

## 1. Что нужно установить один раз

На Mac должен быть доступен `adb`. Самый простой вариант:

1. Установить Android Studio.
2. Открыть Android Studio один раз, чтобы установился Android SDK.
3. Убедиться, что файл существует:

```bash
~/Library/Android/sdk/platform-tools/adb
```

Скрипт сам попробует найти `adb` в этом стандартном месте. Если `adb` уже работает в Terminal, тоже хорошо:

```bash
adb version
```

Также на компьютере должен запускаться проект через Gradle wrapper:

```bash
cd /Users/ashrafkhan/Desktop/My/native-apps/iccu-forum-kiosk
./gradlew --version
```

## 2. Что нужно подготовить на планшете

Перед запуском скрипта планшет должен быть готов:

1. Factory reset или удалены все Google/другие аккаунты.
2. Включён Developer Mode.
3. Включён USB debugging.
4. Планшет подключён USB-кабелем к компьютеру.
5. На планшете подтверждён USB debugging prompt: нажать Allow.

Для первой настройки Device Owner лучше использовать USB, а не Wi-Fi ADB. На некоторых планшетах Wi-Fi ADB падает с ошибкой `closed` во время установки APK.

## 3. Одна команда для установки

Открыть Terminal:

```bash
cd /Users/ashrafkhan/Desktop/My/native-apps/iccu-forum-kiosk
./tools/provision_kiosk_tablet.sh
```

Если подключено несколько планшетов:

```bash
adb devices
./tools/provision_kiosk_tablet.sh --serial DEVICE_SERIAL
```

Пример:

```bash
./tools/provision_kiosk_tablet.sh --serial KZ5CAEJ85LX5DSZFRYW
```

## 4. Что делает скрипт

Скрипт автоматически:

1. Находит подключённый планшет.
2. Собирает APK.
3. Устанавливает APK.
4. Включает Device Owner.
5. Назначает приложение как Home screen.
6. Включает fullscreen/immersive mode.
7. Запускает kiosk app.
8. Проверяет `mLockTaskModeState=LOCKED`.

Если в конце написано:

```text
DONE: tablet ... is ready for kiosk use.
```

значит планшет готов.

## 5. Частые ошибки

### `unauthorized`

На экране планшета нужно нажать Allow для USB debugging.

### `adb not found`

Установить Android Studio или Android Platform Tools. Можно также запустить так:

```bash
ADB=/path/to/adb ./tools/provision_kiosk_tablet.sh
```

### `Device Owner setup failed`

Обычно на планшете есть аккаунт. Нужно удалить аккаунты или сделать factory reset, затем снова включить USB debugging.

### `adb: ... closed`

Чаще бывает по Wi-Fi ADB. Подключить планшет через USB и повторить:

```bash
./tools/provision_kiosk_tablet.sh
```

