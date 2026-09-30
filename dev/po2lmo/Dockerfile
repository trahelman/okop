# po2lmo from LuCI: compiles .po translations into the .lmo files LuCI reads
FROM alpine:3.22 AS build

RUN apk add --no-cache build-base git
RUN git clone --depth 1 --branch openwrt-24.10 --filter=blob:none --sparse https://github.com/openwrt/luci.git /luci && \
    git -C /luci sparse-checkout set modules/luci-base/src
RUN make -C /luci/modules/luci-base/src contrib/lemon lib/plural_formula.c po2lmo

FROM alpine:3.22

COPY --from=build /luci/modules/luci-base/src/po2lmo /usr/bin/po2lmo
