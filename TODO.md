# TODO: заливка весов ML-модели в S3-бакет

## TODO: Android SDK в базовом образе

Для проекта `android` перейти на базовый образ, в котором **уже установлен Android SDK**
(вместо установки SDK «на лету» в build-стадии: `sdkmanager` + `platforms;android-34` +
`build-tools;34.0.0`). Это уберёт многоминутное скачивание SDK на каждом холодном прогоне
(особенно заметно у rootless BuildKit). Варианты:
- `mobiledevops/android-sdk-image` (community);
- свой образ на базе `gradle:8.11.1-jdk17` с предустановленным SDK (`platforms;android-34`,
  `build-tools;34.0.0`) и запушенный в Yandex Container Registry.



Бакет `kaniko-vs-buildkit-weights` создаётся **Terraform'ом** (`weights.tf`, public-read). Файл весов заливается **один раз вручную** — генерировать 1.3 ГБ на каждый `terraform apply` нельзя.

## Какой файл

`google-bert/bert-large-uncased` → `pytorch_model.bin` (**~1.28 ГБ**):

- Source (Hugging Face): `https://huggingface.co/google-bert/bert-large-uncased/resolve/main/pytorch_model.bin`
- В бакет кладётся под ключом `model.bin`
- URL для BUILD-стадии: `https://storage.yandexcloud.net/kaniko-vs-buildkit-weights/model.bin` (выводит `terraform output -raw ml_weights_url`)

## Как залить (одним из способов)

Требуется: Yandex Cloud CLI, авторизация, статические ключи доступа для Object Storage
(создать через `yc iam access-key create --service-account-name ...` или в консоли).

### Вариант A — `mc` (MinIO Client)

```bash
MC_HOST_s3=https://<access_key>:<secret_key>@storage.yandexcloud.net
mc cp pytorch_model.bin s3/kaniko-vs-buildkit-weights/model.bin
```

### Вариант B — AWS CLI (S3-совместимый API)

```bash
AWS_ACCESS_KEY_ID=<access_key> \
AWS_SECRET_ACCESS_KEY=<secret_key> \
aws --endpoint-url=https://storage.yandexcloud.net \
  s3 cp pytorch_model.bin s3://kaniko-vs-buildkit-weights/model.bin
```

### Вариант C — `yc storage` + curl (без доп. клиентов)

```bash
# 1. Скачать модель с HF
curl -fSL -o model.bin https://huggingface.co/google-bert/bert-large-uncased/resolve/main/pytorch_model.bin
# 2. Залить S3-совместимым клиентом (mc/aws) — без этих утилит Yandex CLI
#    не умеет грузить объекты, см. варианты A/B.
```

## Проверка

```bash
curl -sI https://storage.yandexcloud.net/kaniko-vs-buildkit-weights/model.bin \
  | grep -iE "HTTP|content-length"
# ожидаем 200 и content-length ~1344997306
```