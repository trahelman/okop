ARG OPENWRT_IMAGE=openwrt/rootfs:armsr-armv8-24.10.8
ARG OPENWRT_PLATFORM=linux/aarch64_generic
FROM --platform=${OPENWRT_PLATFORM} ${OPENWRT_IMAGE}

# Okop runtime dependencies (see okop/Makefile)
RUN mkdir -p /var/lock && \
    opkg update && \
    opkg install sing-box curl jq kmod-nft-tproxy coreutils-base64 bind-dig && \
    rm -rf /tmp/opkg-lists

COPY devenv devenv-ready /etc/init.d/
RUN /etc/init.d/devenv enable && /etc/init.d/devenv-ready enable

CMD ["/sbin/init"]
