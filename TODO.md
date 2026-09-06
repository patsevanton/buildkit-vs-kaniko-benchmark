# TODO

## TODO: удаление реестра вместе с образами

`terraform destroy` падает с ошибкой: `Registry ... is not empty, you must delete all images first`.
Yandex Container Registry не удаляется, пока в нём есть образы. Нужно доработать `registry.tf`,
чтобы при удалении сначала чистились все образы/репозитории (например, через
`terraform destroy`-provisioner с `yc container image delete`/`repository delete` для всех
репозиториев реестра).

## TODO: Android SDK в базовом образе

Для проекта `android` перейти на базовый образ, в котором **уже установлен Android SDK**
(вместо установки SDK «на лету» в build-стадии: `sdkmanager` + `platforms;android-34` +
`build-tools;34.0.0`). Это уберёт многоминутное скачивание SDK на каждом холодном прогоне
(особенно заметно у rootless BuildKit). Варианты:
- `mobiledevops/android-sdk-image` (community);
- свой образ на базе `gradle:8.11.1-jdk17` с предустановленным SDK (`platforms;android-34`,
  `build-tools;34.0.0`) и запушенный в Yandex Container Registry.
