FROM ubuntu:20.04

LABEL org.opencontainers.image.title="Versal Boot GUI" \
      org.opencontainers.image.description="Qt GUI for Versal JTAG and QSPI boot workflows" \
      org.opencontainers.image.version="2025.2"

ENV DEBIAN_FRONTEND=noninteractive
ENV QT_X11_NO_MITSHM=1
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    locales \
    u-boot-tools \
    libgl1 \
    libx11-6 \
    libxcb1 \
    libxcb-xinerama0 \
    libxkbcommon-x11-0 \
    libqt5core5a \
    libqt5concurrent5 \
    libqt5gui5 \
    libqt5network5 \
    libqt5qml5 \
    libqt5quick5 \
    libqt5quickcontrols2-5 \
    libyaml-0-2 \
    qml-module-qt-labs-folderlistmodel \
    qml-module-qt-labs-settings \
    qml-module-qtquick2 \
    qml-module-qtquick-controls \
    qml-module-qtquick-controls2 \
    qml-module-qtquick-layouts \
    qml-module-qtquick-dialogs \
    qml-module-qtquick-window2 \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/qt-boot-gui/configs /opt/qt-boot-gui/licenses \
    && cp /usr/share/common-licenses/LGPL-3 /opt/qt-boot-gui/licenses/LGPL-3.0.txt

COPY qt_boot_gui /opt/qt-boot-gui/qt_boot_gui
COPY jtag_config.json qspi_config.json /opt/qt-boot-gui/configs/
COPY LICENSES/THIRD_PARTY_NOTICES.md /opt/qt-boot-gui/licenses/THIRD_PARTY_NOTICES.md
COPY docker-entrypoint.sh /usr/local/bin/qt-boot-gui-entrypoint

RUN chmod 755 \
    /opt/qt-boot-gui/qt_boot_gui \
    /usr/local/bin/qt-boot-gui-entrypoint

ENTRYPOINT ["/usr/local/bin/qt-boot-gui-entrypoint"]
