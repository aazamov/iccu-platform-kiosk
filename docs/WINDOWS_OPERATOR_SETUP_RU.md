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
2. Пробует включить Wi-Fi и подключить планшет к `Neo_wifi`.
3. Проверяет Android System WebView.
4. Если WebView старый, обновляет его из локального APK.
5. Собирает APK.
6. Устанавливает APK.
7. Включает Device Owner.
8. Назначает приложение как Home screen.
9. Включает fullscreen/immersive mode.
10. Запускает kiosk app.
11. Проверяет `mLockTaskModeState=LOCKED`.

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

Если на планшете старый WebView, скрипт попробует сам скачать Android System WebView APK в:

```text
C:\Kiosk\iccu-forum-kiosk\tools\.downloads\android-system-webview.apk
```

Для стабильной работы на трёх Windows-компьютерах лучше один раз скачать APK и заранее скопировать его в эту папку на каждый компьютер.

Для HK17 Pro Max / Android 10 нужен WebView:

```text
package: com.google.android.webview
arch: arm64-v8a + armeabi-v7a
minimum Android: Android 10 / API 29
```

Можно также положить файл с именем:

```text
tools\.downloads\android-system-webview-150.apk
```

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

Если подключено несколько планшетов, скрипт установит kiosk на все планшеты со статусом `device`.

Если нужно установить только на один конкретный планшет, сначала посмотреть serial:

```powershell
adb devices
```

Потом запустить с serial:

```powershell
tools\provision_kiosk_tablet.bat -Serial KZ5CAEJ85LX5DSZFRYW
```

Если нужно вернуть старое поведение и запретить автоматическую установку на несколько планшетов:

```powershell
tools\provision_kiosk_tablet.bat -SingleDevice
```

По умолчанию скрипт подключает каждый планшет к Wi-Fi:

```text
SSID: Neo_wifi
```

На некоторых HK17 прошивках Android запрещает ADB-команду `cmd wifi connect-network` и пишет:

```text
Security exception: Uid 2000 does not have access to wifi commands
```

Это нормально. В такой ситуации актуальный скрипт не останавливает установку: он устанавливает kiosk app, включает Device Owner и затем отправляет команду Wi-Fi уже внутрь kiosk app.

Если нужно указать другую сеть:

```powershell
tools\provision_kiosk_tablet.bat -WifiSsid "OfficeWifi" -WifiPassword "password"
```

Если Wi-Fi уже настроен вручную и этот шаг нужно пропустить:

```powershell
tools\provision_kiosk_tablet.bat -SkipWifiSetup
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

Если нужно указать свой путь к WebView APK:

```powershell
tools\provision_kiosk_tablet.bat -WebViewApk C:\Kiosk\android-system-webview.apk
```

Если нужно указать свежую прямую ссылку для скачивания WebView APK:

```powershell
tools\provision_kiosk_tablet.bat -WebViewApkUrl https://example.com/android-system-webview.apk
```

Если планшет уже обновлён и проверку WebView нужно пропустить:

```powershell
tools\provision_kiosk_tablet.bat -SkipWebViewUpdate
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

Можно подключить несколько планшетов через USB hub. Скрипт соберёт APK один раз, потом установит приложение на каждый планшет по очереди и покажет summary.

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

### `DexArchiveMergerException` или `defined multiple times`

Это обычно stale/corrupted Gradle cache на Windows после обновления проекта. Актуальная версия `tools\provision_kiosk_tablet.bat` сама делает повторную сборку через `gradlew.bat clean ...`.

Если ошибка осталась, вручную запустить:

```powershell
gradlew.bat clean
tools\provision_kiosk_tablet.bat
```

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
