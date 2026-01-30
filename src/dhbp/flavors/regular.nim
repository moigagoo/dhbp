#? stdtmpl
#proc ubuntu*(version: string, labels: openarray[(string, string)] = {:}): string =
#  result = ""
FROM ubuntu:noble

ENV NIM_VERSION=$version
ENV PATH="/usr/local/bin:/root/.nimble/bin:$${PATH}"

#  for label, value in labels.items:
LABEL $label="$value"
#  end for

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        g++ \
        git \
        libssl-dev \
        mercurial \
        nodejs \
        wget \
        xz-utils \
    ; \
    \
    wget -O nim.tar.xz "https://nim-lang.org/download/nim-${NIM_VERSION}.tar.xz"; \
    mkdir -p /usr/local/src/nim; \
    tar -xf nim.tar.xz -C /usr/local/src/nim --strip-components=1; \
    rm nim.tar.xz; \
    \
    cd /usr/local/src/nim; \
    sh build.sh; \
    \
    bin/nim c koch; \
    ./koch tools; \
    \
    ln -s /usr/local/src/nim/bin/nim /usr/local/bin/nim; \
    ln -s /usr/local/src/nim/bin/nimble /usr/local/bin/nimble; \
    ln -s /usr/local/src/nim/bin/nimsuggest /usr/local/bin/nimsuggest; \
    ln -s /usr/local/src/nim/bin/testament /usr/local/bin/testament; \
    \
    rm -rf /usr/local/src/nim/c_code /usr/local/src/nim/tests; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
CMD ["nim", "--version"]
#end proc
#
#proc alpine*(version: string, labels: openarray[(string, string)] = {:}): string =
#  result = ""
FROM alpine:3.20

ENV NIM_VERSION=$version
ENV PATH="/usr/local/bin:/root/.nimble/bin:$${PATH}"

#  for label, value in labels.items:
LABEL $label="$value"
#  end for

RUN set -eux; \
    apk add --no-cache \
        ca-certificates \
        g++ \
        git \
        libgcc \
        mercurial \
        nodejs \
        openssl-dev \
        wget \
        xz \
    ; \
    \
    wget -O nim.tar.xz "https://nim-lang.org/download/nim-${NIM_VERSION}.tar.xz"; \
    mkdir -p /usr/local/src/nim; \
    tar -xf nim.tar.xz -C /usr/local/src/nim --strip-components=1; \
    rm nim.tar.xz; \
    \
    cd /usr/local/src/nim; \
    sh build.sh; \
    \
    bin/nim c koch; \
    ./koch tools; \
    \
    ln -s /usr/local/src/nim/bin/nim /usr/local/bin/nim; \
    ln -s /usr/local/src/nim/bin/nimble /usr/local/bin/nimble; \
    ln -s /usr/local/src/nim/bin/nimsuggest /usr/local/bin/nimsuggest; \
    ln -s /usr/local/src/nim/bin/testament /usr/local/bin/testament; \
    \
    rm -rf /usr/local/src/nim/c_code /usr/local/src/nim/tests

WORKDIR /app
CMD ["nim", "--version"]
#end proc
