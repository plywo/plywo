# syntax=docker/dockerfile:1

ARG RUBY_VERSION=3.4.10
ARG NODE_VERSION=24.20.0
ARG NPM_VERSION=11.19.0
ARG PNPM_VERSION=12.3.4

FROM node:${NODE_VERSION}-slim AS node_runtime
ARG PNPM_VERSION
RUN npm install --global "pnpm@${PNPM_VERSION}" && \
    test "$(pnpm --version)" = "${PNPM_VERSION}"

FROM ruby:${RUBY_VERSION}-slim

ARG RUBY_VERSION
ARG NODE_VERSION
ARG NPM_VERSION
ARG PNPM_VERSION

WORKDIR /app

ENV BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=development \
    PLYWO_EXECUTOR_CAPABILITIES_JSON="{\"runtimes\":{\"ruby\":\"${RUBY_VERSION}\",\"node\":\"${NODE_VERSION}\"},\"package_managers\":{\"npm\":\"${NPM_VERSION}\",\"pnpm\":\"${PNPM_VERSION}\"}}"

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential \
      git \
      libpq-dev \
      libsqlite3-dev \
      pkg-config && \
    rm -rf /var/lib/apt/lists/*

COPY --from=node_runtime /usr/local/bin/node /usr/local/bin/node
COPY --from=node_runtime /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
COPY --from=node_runtime /usr/local/lib/node_modules/pnpm /usr/local/lib/node_modules/pnpm

RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
    ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx && \
    PNPM_BIN="$(node -p "require('/usr/local/lib/node_modules/pnpm/package.json').bin.pnpm")" && \
    PNPX_BIN="$(node -p "require('/usr/local/lib/node_modules/pnpm/package.json').bin.pnpx")" && \
    ln -s "../lib/node_modules/pnpm/${PNPM_BIN}" /usr/local/bin/pnpm && \
    ln -s "../lib/node_modules/pnpm/${PNPX_BIN}" /usr/local/bin/pnpx && \
    test "$(node --version)" = "v${NODE_VERSION}" && \
    test "$(npm --version)" = "${NPM_VERSION}" && \
    test "$(pnpm --version)" = "${PNPM_VERSION}"

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .
RUN bundle exec ruby script/prove_node_npm_executor_capability.rb && \
    bundle exec ruby script/prove_pnpm_executor_capability.rb

ENV RAILS_ENV=production \
    RAILS_LOG_TO_STDOUT=1

EXPOSE 3000

CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
