ARG DEBIAN_DIST=bookworm
FROM debian:$DEBIAN_DIST

ARG DEBIAN_DIST
ARG bottom_VERSION
ARG BUILD_VERSION
ARG FULL_VERSION
ARG ARCH
ARG DEPENDS
ARG BOTTOM_RELEASE

RUN mkdir -p /output/usr/bin
RUN mkdir -p /output/usr/share/doc/btm
RUN mkdir -p /output/usr/share/man/man1
RUN mkdir -p /output/usr/share/bash-completion/completions
RUN mkdir -p /output/usr/share/fish/vendor_completions.d
RUN mkdir -p /output/usr/share/zsh/vendor-completions
RUN mkdir -p /output/usr/share/applications
RUN mkdir -p /output/usr/share/icons/hicolor/scalable/apps
RUN mkdir -p /output/DEBIAN

COPY ${BOTTOM_RELEASE}/btm /output/usr/bin/
COPY ${BOTTOM_RELEASE}/manpage/btm.1 /output/usr/share/man/man1/
COPY ${BOTTOM_RELEASE}/completion/btm.bash /output/usr/share/bash-completion/completions/btm
COPY ${BOTTOM_RELEASE}/completion/btm.fish /output/usr/share/fish/vendor_completions.d/
COPY ${BOTTOM_RELEASE}/completion/_btm /output/usr/share/zsh/vendor-completions/
COPY ${BOTTOM_RELEASE}/desktop/bottom.desktop /output/usr/share/applications/
COPY ${BOTTOM_RELEASE}/icons/bottom-system-monitor.svg /output/usr/share/icons/hicolor/scalable/apps/
RUN gzip -9n /output/usr/share/man/man1/*.1
COPY output/DEBIAN/control /output/DEBIAN/
COPY output/DEBIAN/postinst /output/DEBIAN/postinst
RUN chmod 755 /output/DEBIAN/postinst
RUN chmod 755 /output/usr/bin/btm
COPY output/copyright /output/usr/share/doc/btm/
COPY output/changelog.Debian /output/usr/share/doc/btm/
COPY output/README.md /output/usr/share/doc/btm/

RUN sed -i "s/DIST/$DEBIAN_DIST/" /output/usr/share/doc/btm/changelog.Debian
RUN sed -i "s/FULL_VERSION/$FULL_VERSION/" /output/usr/share/doc/btm/changelog.Debian
RUN sed -i "s/DIST/$DEBIAN_DIST/" /output/DEBIAN/control
RUN sed -i "s/bottom_VERSION/$bottom_VERSION/" /output/DEBIAN/control
RUN sed -i "s/BUILD_VERSION/$BUILD_VERSION/" /output/DEBIAN/control
RUN sed -i "s/SUPPORTED_ARCHITECTURES/$ARCH/" /output/DEBIAN/control
RUN sed -i "s|DEPENDS|$DEPENDS|" /output/DEBIAN/control

RUN find /output/usr/share -type f -exec chmod 644 {} +

RUN dpkg-deb --build /output /btm_${FULL_VERSION}.deb
