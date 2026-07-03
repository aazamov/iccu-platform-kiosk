# ICCU Forum Kiosk: установка на планшет

Эта инструкция для ситуации, когда проект уже есть на компьютере. Ничего создавать заново не нужно. Нужно только собрать APK, установить приложение на планшет и включить kiosk mode.

## Быстрый способ для оператора

Если компьютер уже настроен, а планшет уже подготовлен: включён Developer Mode, включён USB debugging, debugging permission подтверждён, аккаунтов на планшете нет, то оператору нужна только одна команда.

Открыть Terminal в папке проекта:

```bash
cd /Users/ashrafkhan/Desktop/My/native-apps/iccu-forum-kiosk
```

Подключить один планшет к компьютеру и запустить:

```bash
./tools/provision_kiosk_tablet.sh
```

Скрипт сам сделает:

1. Найдёт подключённый планшет через `adb`.
2. Соберёт APK.
3. Установит приложение на планшет.
4. Включит Device Owner.
5. Назначит приложение как Home screen.
6. Включит fullscreen/immersive mode.
7. Запустит приложение.
8. Проверит, что kiosk mode включён: `mLockTaskModeState=LOCKED`.

Если подключено несколько планшетов, нужно указать serial:

```bash
adb devices
./tools/provision_kiosk_tablet.sh --serial KZ5CAEJ85LX5DSZFRYW
```

Для повторной установки, когда APK уже собран:

```bash
./tools/provision_kiosk_tablet.sh --skip-build
```

Если скрипт завершился строкой ниже, планшет готов:

```text
DONE: tablet ... is ready for kiosk use.
```

Отдельная короткая инструкция для настройки компьютера оператора находится здесь:

```text
docs/OPERATOR_COMPUTER_SETUP_RU.md
```

Для Windows-компьютеров используйте отдельную инструкцию:

```text
docs/WINDOWS_OPERATOR_SETUP_RU.md
```

## 1. Что уже должно быть готово

На компьютере должна быть папка проекта:

```bash
/Users/ashrafkhan/Desktop/My/native-apps/iccu-forum-kiosk
```

Внутри проекта уже есть Android-приложение:

```text
ICCU Forum Kiosk
```

Приложение открывает сайт:

```text
https://forum.iccu.uz/
```

Package name:

```text
uz.neovex.iccu.kiosk
```

Главный экран:

```text
uz.neovex.iccu.kiosk/.MainActivity
```

Device Owner receiver:

```text
uz.neovex.iccu.kiosk/.KioskDeviceAdminReceiver
```

PIN для выхода из kiosk:

```text
2026
```

## 2. Что нужно на компьютере

На Mac должны работать команды:

```bash
adb version
java -version
```

Также в проекте должен запускаться Gradle wrapper:

```bash
./gradlew --version
```

Если `adb` не найден, нужно установить Android Platform Tools или открыть Terminal через Android Studio environment.

## 3. Открыть проект в Terminal

В Terminal перейти в папку проекта:

```bash
cd /Users/ashrafkhan/Desktop/My/native-apps/iccu-forum-kiosk
```

Все команды ниже выполнять из этой папки.

## 4. Подготовить планшет

На планшете нужно:

1. Включить Developer options.
2. Включить USB debugging или Wireless debugging.
3. Подключить планшет к компьютеру.
4. Подтвердить RSA/debugging permission на экране планшета.

Для полноценного kiosk mode нужно, чтобы на планшете не было Google account или других accounts. Если аккаунты есть, команда Device Owner может не сработать.

Проверить подключение:

```bash
adb devices
```

Нормальный результат:

```text
List of devices attached
KZ5CAEJ85LX5DSZFRYW    device
```

Если написано `unauthorized`, посмотрите на экран планшета и нажмите Allow.

Если планшет подключён по Wi-Fi ADB, сначала подключиться:

```bash
adb connect 192.168.68.61:5555
adb devices
```

## 5. Выбрать serial планшета

Если подключён один планшет, можно писать команды без `-s`.

Если устройств несколько, используйте serial. Например:

```bash
KZ5CAEJ85LX5DSZFRYW
```

Дальше в инструкции все команды написаны с serial `KZ5CAEJ85LX5DSZFRYW`. Если у вашего планшета другой serial, замените `KZ5CAEJ85LX5DSZFRYW` на свой.

## 6. Собрать APK

В папке проекта выполнить:

```bash
./gradlew testDebugUnitTest assembleDebug
```

Если всё хорошо, в конце будет:

```text
BUILD SUCCESSFUL
```

APK будет здесь:

```text
app/build/outputs/apk/debug/app-debug.apk
```

## 7. Установить APK на планшет

```bash
adb -s KZ5CAEJ85LX5DSZFRYW install -r app/build/outputs/apk/debug/app-debug.apk
```

Нормальный результат:

```text
Performing Streamed Install
Success
```

Если появляется ошибка `closed`, перезапустите ADB:

```bash
adb kill-server
adb start-server
adb devices
adb -s KZ5CAEJ85LX5DSZFRYW install -r app/build/outputs/apk/debug/app-debug.apk
```

## 8. Включить Device Owner

Device Owner нужен, чтобы kiosk был настоящим: пользователь не сможет выйти через Home/Back/Recent.

Команда:

```bash
adb -s KZ5CAEJ85LX5DSZFRYW shell dpm set-device-owner uz.neovex.iccu.kiosk/.KioskDeviceAdminReceiver
```

Успешный результат:

```text
Success: Device owner set to package ComponentInfo{uz.neovex.iccu.kiosk/uz.neovex.iccu.kiosk.KioskDeviceAdminReceiver}
```

Проверить:

```bash
adb -s KZ5CAEJ85LX5DSZFRYW shell dpm get-device-owner
```

Если Android пишет, что Device Owner нельзя включить из-за аккаунтов, удалите аккаунты с планшета. Если не помогает, сделайте factory reset, не добавляйте аккаунт и повторите установку.

## 9. Сделать приложение главным экраном

Назначить kiosk app как Home activity:

```bash
adb -s KZ5CAEJ85LX5DSZFRYW shell cmd package set-home-activity uz.neovex.iccu.kiosk/.MainActivity
```

Скрыть системные панели:

```bash
adb -s KZ5CAEJ85LX5DSZFRYW shell settings put global policy_control 'immersive.full=*'
```

Запустить приложение:

```bash
adb -s KZ5CAEJ85LX5DSZFRYW shell monkey -p uz.neovex.iccu.kiosk 1
```

## 10. Проверить, что kiosk включён

```bash
adb -s KZ5CAEJ85LX5DSZFRYW shell dumpsys activity activities | rg -i 'mLockTaskModeState|uz.neovex' -C 2
```

Нужно увидеть:

```text
mLockTaskModeState=LOCKED
```

Если `LOCKED` есть, kiosk работает правильно.

## 11. Проверить автозапуск после выключения/включения

Перезагрузить планшет:

```bash
adb -s KZ5CAEJ85LX5DSZFRYW reboot
```

Подождать загрузку устройства. Потом проверить:

```bash
adb devices
adb -s KZ5CAEJ85LX5DSZFRYW shell dumpsys activity activities | rg -i 'mLockTaskModeState|uz.neovex' -C 2
```

Ожидаемый результат:

```text
uz.neovex.iccu.kiosk/.MainActivity
mLockTaskModeState=LOCKED
```

## 12. Одна команда для полной установки

Эту команду можно использовать, когда планшет уже подключён и Device Owner либо уже включён, либо будет включаться отдельно.

```bash
./gradlew testDebugUnitTest assembleDebug && \
adb -s KZ5CAEJ85LX5DSZFRYW install -r app/build/outputs/apk/debug/app-debug.apk && \
adb -s KZ5CAEJ85LX5DSZFRYW shell settings put global policy_control 'immersive.full=*' && \
adb -s KZ5CAEJ85LX5DSZFRYW shell cmd package set-home-activity uz.neovex.iccu.kiosk/.MainActivity && \
adb -s KZ5CAEJ85LX5DSZFRYW shell am force-stop uz.neovex.iccu.kiosk && \
adb -s KZ5CAEJ85LX5DSZFRYW shell monkey -p uz.neovex.iccu.kiosk 1 && \
sleep 10 && \
adb -s KZ5CAEJ85LX5DSZFRYW shell dumpsys activity activities | rg -i 'mLockTaskModeState|uz.neovex' -C 2
```

Если это первая установка после factory reset, сначала выполните отдельно Device Owner command:

```bash
adb -s KZ5CAEJ85LX5DSZFRYW shell dpm set-device-owner uz.neovex.iccu.kiosk/.KioskDeviceAdminReceiver
```

## 13. Как пользоваться после установки

Обычный пользователь:

- видит сайт `https://forum.iccu.uz/`;
- не может выйти кнопками Back/Home/Recent;
- не может открыть нижнюю системную панель;
- не может масштабировать страницу;
- не может выделять текст.

Админ:

- Wi-Fi: нажать Wi-Fi icon один раз.
- Brightness: нажать brightness icon один раз, затем менять яркость кнопками `-`/`+` или slider.
- Reload сайта с очисткой cache: держать battery area 3 секунды.
- Exit: держать скрытую зону сверху слева 5 секунд, ввести PIN `2026`.

## 14. Обновить приложение на планшете

Если приложение уже стоит и Device Owner уже включён, повторять `dpm set-device-owner` не нужно.

Собрать:

```bash
./gradlew testDebugUnitTest assembleDebug
```

Установить поверх:

```bash
adb -s KZ5CAEJ85LX5DSZFRYW install -r app/build/outputs/apk/debug/app-debug.apk
```

Перезапустить:

```bash
adb -s KZ5CAEJ85LX5DSZFRYW shell am force-stop uz.neovex.iccu.kiosk
adb -s KZ5CAEJ85LX5DSZFRYW shell monkey -p uz.neovex.iccu.kiosk 1
```

Проверить:

```bash
adb -s KZ5CAEJ85LX5DSZFRYW shell dumpsys activity activities | rg -i 'mLockTaskModeState|uz.neovex' -C 2
```

Должно быть:

```text
mLockTaskModeState=LOCKED
```

## 15. Если нужно выйти или удалить приложение

Выйти из kiosk:

1. Нажать скрытую зону сверху слева.
2. Держать 5 секунд.
3. Ввести PIN `2026`.

Удаление Device Owner не всегда разрешено Android через ADB. Если нужно полностью снять kiosk с планшета, самый надёжный вариант:

1. Выйти из приложения через PIN.
2. Сделать factory reset планшета.

Если Android разрешает снять admin, можно попробовать:

```bash
adb -s KZ5CAEJ85LX5DSZFRYW shell dpm remove-active-admin uz.neovex.iccu.kiosk/.KioskDeviceAdminReceiver
adb -s KZ5CAEJ85LX5DSZFRYW uninstall uz.neovex.iccu.kiosk
```

## 16. Частые проблемы

### Планшет не виден в `adb devices`

Проверить USB cable, USB mode и debugging permission.

Перезапустить ADB:

```bash
adb kill-server
adb start-server
adb devices
```

### `unauthorized`

На планшете нажать Allow для RSA prompt.

Если prompt не появляется:

```bash
adb kill-server
adb start-server
```

Потом выключить и включить USB debugging на планшете.

### `adb: failed to run abb_exec. Error: closed`

```bash
adb kill-server
adb start-server
adb devices
adb -s KZ5CAEJ85LX5DSZFRYW install -r app/build/outputs/apk/debug/app-debug.apk
```

Если используется Wi-Fi ADB:

```bash
adb disconnect
adb connect 192.168.68.61:5555
```

### Device Owner не включается

Проверить:

- APK установлен;
- на планшете нет Google account;
- package name правильный;
- нет другого Device Owner.

Команды:

```bash
adb -s KZ5CAEJ85LX5DSZFRYW shell pm list packages | rg uz.neovex
adb -s KZ5CAEJ85LX5DSZFRYW shell dpm get-device-owner
adb -s KZ5CAEJ85LX5DSZFRYW shell dumpsys account
```

### Белый экран

Проверить интернет на планшете.

Перезапустить приложение:

```bash
adb -s KZ5CAEJ85LX5DSZFRYW shell am force-stop uz.neovex.iccu.kiosk
adb -s KZ5CAEJ85LX5DSZFRYW shell monkey -p uz.neovex.iccu.kiosk 1
```

Или держать battery area 3 секунды, чтобы сделать hard reload.

### Нижняя панель Android появилась

Повторить:

```bash
adb -s KZ5CAEJ85LX5DSZFRYW shell settings put global policy_control 'immersive.full=*'
adb -s KZ5CAEJ85LX5DSZFRYW shell monkey -p uz.neovex.iccu.kiosk 1
```

Проверить:

```bash
adb -s KZ5CAEJ85LX5DSZFRYW shell dumpsys activity activities | rg -i 'mLockTaskModeState' -C 2
```

## 17. Финальный чеклист

Перед передачей планшета проверить:

- `adb devices` видит планшет.
- `./gradlew testDebugUnitTest assembleDebug` заканчивается `BUILD SUCCESSFUL`.
- APK установлен с результатом `Success`.
- Device Owner включён.
- Home activity назначен на `uz.neovex.iccu.kiosk/.MainActivity`.
- Приложение запускается и открывает `https://forum.iccu.uz/`.
- `mLockTaskModeState=LOCKED`.
- После reboot приложение открывается автоматически.
- Wi-Fi открывается обычным нажатием.
- Brightness control с `-`, slider и `+` открывается обычным нажатием.
- Battery hard reload работает long press 3 секунды.
- Hidden exit работает long press 5 секунд + PIN `2026`.
