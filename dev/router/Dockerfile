ARG OPENWRT_IMAGE=openwrt/rootfs:armsr-armv8-24.10.8
ARG OPENWRT_PLATFORM=linux/aarch64_generic
FROM --platform=${OPENWRT_PLATFORM} ${OPENWRT_IMAGE}

# Okop runtime dependencies (see okop/Makefile)
RUN mkdir -p /var/lock && \
    opkg update && \
    opkg install sing-box curl jq kmod-nft-tproxy coreutils-base64 bind-dig && \
    rm -rf /tmp/opkg-lists

# okop sources are mounted from the repository by compose.yml
RUN ln -s /opt/okop/usr/bin/okop /usr/bin/okop && \
    ln -s /opt/okop/usr/lib /usr/lib/okop && \
    ln -s /opt/okop/etc/init.d/okop /etc/init.d/okop && \
    ln -s /opt/luci-app-okop/htdocs/luci-static/resources/view/okop /www/luci-static/resources/view/okop && \
    ln -s /opt/luci-app-okop/root/usr/share/luci/menu.d/luci-app-okop.json /usr/share/luci/menu.d/ && \
    ln -s /opt/luci-app-okop/root/usr/share/rpcd/acl.d/luci-app-okop.json /usr/share/rpcd/acl.d/

COPY devenv devenv-ready /etc/init.d/
RUN /etc/init.d/devenv enable && /etc/init.d/devenv-ready enable

CMD ["/sbin/init"]
