# Multi-stage Dockerfile — проект android (Gradle assembleRelease → APK).
# Gradle и Android SDK ставятся на лету в build-стадии (как и в реальном CI).
# Runtime-стадия простая: apk файл кладётся на базовый образ.
FROM gradle:8.10-jdk17 AS builder
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV JAVA_HOME=/opt/java/openjdk
RUN apt-get update \
    && apt-get install -y --no-install-recommends unzip git \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p ${ANDROID_HOME}/cmdline-tools
ARG SDK_VERSION=11076708
RUN curl -fSL -o /tmp/cmdline-tools.zip \
      https://dl.google.com/android/repository/commandlinetools-linux-${SDK_VERSION}_latest.zip \
    && unzip -q /tmp/cmdline-tools.zip -d ${ANDROID_HOME}/cmdline-tools \
    && mv ${ANDROID_HOME}/cmdline-tools/cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest \
    && rm /tmp/cmdline-tools.zip \
    && yes | ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager --licenses >/dev/null 2>&1 \
    && ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager \
         "platforms;android-34" \
         "build-tools;34.0.0" >/dev/null 2>&1

WORKDIR /src
COPY settings.gradle ./
COPY build.gradle ./
COPY gradle.properties ./
COPY app/build.gradle ./app/build.gradle
COPY app/src ./app/src
RUN gradle --no-daemon assembleRelease

FROM openjdk:17-slim
COPY --from=builder /src/app/build/outputs/apk/release/app-release.apk /app-release.apk
EXPOSE 8080
CMD ["/bin/sh", "-c", "ls -la /app-release.apk && tail -f /dev/null"]