# Настройка 3 Windows-компьютеров для установки kiosk на планшеты

Эта инструкция нужна, чтобы на каждом Windows-компьютере ребята могли подключить подготовленный планшет и запустить установку одной командой.

## 1. Что получится в итоге

На каждом Windows-компьютере будет папка проекта, например:

```text
C:\Kiosk\iccu-forum-kiosk
```

Оператор подключает планшет USB-кабелем и запускает:

```bat
tools\provision_kiosk_tablet.bat
```

Скрипт сам делает:

1. Находит подключённый планшет через ADB.
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

планшет готов.

## 2. Что установить на каждый Windows-компьютер

Вручную устанавливать Java и ADB не обязательно.

Скрипт сам проверит:

- есть ли Java 17;
- есть ли Android SDK для сборки;
- есть ли `adb.exe`.

Если их нет, скрипт сам скачает portable tools внутрь проекта:

```text
C:\Kiosk\iccu-forum-kiosk\tools\.portable
```

Первый запуск на новом Windows-компьютере требует интернет, потому что будут скачаны:

- Temurin JDK 17;
- Android SDK Command-line Tools;
- Android SDK Platform Tools;
- Android platform `android-36`;
- Android build-tools `36.0.0`.

После первого запуска интернет для Java/Android SDK/ADB уже не нужен, потому что tools будут лежать локально в `tools\.portable`.

Если на компьютере уже установлены Java 17 и ADB, скрипт использует их.

### USB driver

Если Windows не видит планшет через `adb devices`, нужно поставить USB-драйвер производителя планшета или Google USB Driver.

Проверка:

```powershell
adb devices
```

Нормально:

```text
List of devices attached
KZ5CAEJ85LX5DSZFRYW    device
```

Если `unauthorized`, нужно на планшете нажать Allow для USB debugging.

## 3. Скопировать проект на Windows

На каждом из 3 компьютеров создать папку:

```text
C:\Kiosk
```

Скопировать проект целиком:

```text
C:\Kiosk\iccu-forum-kiosk
```

Внутри должны быть файлы:

```text
gradlew
gradlew.bat
settings.gradle.kts
app\
tools\provision_kiosk_tablet.ps1
tools\provision_kiosk_tablet.bat
tools\uninstall_kiosk_tablet.ps1
tools\uninstall_kiosk_tablet.bat
```

## 4. Первый тест на Windows

Открыть PowerShell:

```powershell
cd C:\Kiosk\iccu-forum-kiosk
tools\provision_kiosk_tablet.bat -PrepareTools
```

Эта команда скачает portable Java 17, Android SDK и ADB в `tools\.portable`, даже если планшет ещё не подключён.

Для проверки только сборки APK без планшета:

```powershell
tools\provision_kiosk_tablet.bat -BuildOnly -NoTests
```

Сборка должна закончиться:

```text
BUILD SUCCESSFUL
```

APK появится здесь:

```text
app\build\outputs\apk\debug\app-debug.apk
```

## 5. Подготовка планшета

Перед запуском скрипта планшет должен быть подготовлен:

1. Factory reset или удалены все Google/другие аккаунты.
2. Включён Developer Mode.
3. Включён USB debugging.
4. Планшет подключён к Windows-компьютеру USB-кабелем.
5. На экране планшета подтверждён USB debugging prompt: Allow.

Для первой настройки Device Owner используйте USB. Wi-Fi ADB может быть нестабильным и иногда падает с ошибкой `closed`.

## 6. Установка одной командой

Открыть PowerShell или Command Prompt:

```powershell
cd C:\Kiosk\iccu-forum-kiosk
tools\provision_kiosk_tablet.bat
```

Если подключено несколько планшетов, сначала посмотреть serial:

```powershell
adb devices
```

Потом запустить с serial:

```powershell
tools\provision_kiosk_tablet.bat -Serial KZ5CAEJ85LX5DSZFRYW
```

Если APK уже собран и нужно быстрее:

```powershell
tools\provision_kiosk_tablet.bat -SkipBuild
```

Если нужно пропустить unit tests:

```powershell
tools\provision_kiosk_tablet.bat -NoTests
```

Если нужно только заранее скачать portable Java/Android SDK/ADB:

```powershell
tools\provision_kiosk_tablet.bat -PrepareTools
```

Если нужно только собрать APK без планшета:

```powershell
tools\provision_kiosk_tablet.bat -BuildOnly
```

## 7. Удаление kiosk-приложения с планшета

Если нужно убрать приложение с планшета, подключить планшет по USB и запустить:

```powershell
cd C:\Kiosk\iccu-forum-kiosk
tools\uninstall_kiosk_tablet.bat
```

Скрипт автоматически:

1. Находит подключённый планшет через ADB.
2. Проверяет, установлен ли пакет `uz.neovex.iccu.kiosk`.
3. Если приложение является Device Owner, собирает/устанавливает debug APK с remove hook.
4. Снимает Device Owner внутри приложения.
5. Удаляет пакет `uz.neovex.iccu.kiosk`.
6. Проверяет, что пакет больше не установлен.

Если APK уже собран и нужно быстрее:

```powershell
tools\uninstall_kiosk_tablet.bat -SkipBuild
```

Если подключено несколько планшетов:

```powershell
tools\uninstall_kiosk_tablet.bat -Serial KZ5CAEJ85LX5DSZFRYW
```

## 8. Что делать на трёх компьютерах

На каждом Windows-компьютере один раз:

1. Скопировать проект в `C:\Kiosk\iccu-forum-kiosk`.
2. Убедиться, что есть интернет для первого запуска.
3. Установить USB-драйвер планшета, если Windows не видит планшет.
4. Запустить `tools\provision_kiosk_tablet.bat` один раз, чтобы скрипт сам скачал portable Java/Android SDK/ADB и установил первый планшет.

После этого каждый оператор делает только:

```powershell
cd C:\Kiosk\iccu-forum-kiosk
tools\provision_kiosk_tablet.bat
```

Для удаления приложения:

```powershell
cd C:\Kiosk\iccu-forum-kiosk
tools\uninstall_kiosk_tablet.bat
```

## 9. Частые ошибки

### Нет Java, Android SDK или ADB

Ничего устанавливать вручную не нужно. Запустите:

```powershell
tools\provision_kiosk_tablet.bat
```

Скрипт сам скачает portable Java 17, Android SDK и Android platform-tools.

Если интернет запрещён, подготовьте папку `tools\.portable` заранее на одном компьютере и скопируйте её на остальные компьютеры.

### `unauthorized`

На планшете нажать Allow для USB debugging. Потом снова:

```powershell
adb devices
```

### Планшет не виден

Проверить:

- USB-кабель поддерживает data, не только charging;
- USB debugging включён;
- установлен USB-драйвер;
- в Device Manager нет устройства с ошибкой.

Перезапустить ADB:

```powershell
adb kill-server
adb start-server
adb devices
```

### `Device Owner setup failed`

Обычно причина: на планшете есть Google account или другой account.

Решение:

1. Factory reset.
2. Не добавлять Google account.
3. Включить Developer Mode.
4. Включить USB debugging.
5. Запустить script снова.

### `adb: ... closed`

Чаще бывает через Wi-Fi ADB. Для первой установки подключить планшет через USB и повторить:

```powershell
tools\provision_kiosk_tablet.bat
```

## 9. Проверка готового планшета

После успешной установки можно проверить:

```powershell
adb shell dumpsys activity activities | findstr /i "mLockTaskModeState uz.neovex"
```

Должно быть:

```text
mLockTaskModeState=LOCKED
```
