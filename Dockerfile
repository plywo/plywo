# syntax=docker/dockerfile:1

ARG RUBY_VERSION=3.4.10
ARG NODE_VERSION=24.20.0
ARG NPM_VERSION=11.19.0

FROM node:${NODE_VERSION}-slim AS node_runtime

FROM ruby:${RUBY_VERSION}-slim

ARG RUBY_VERSION
ARG NODE_VERSION
ARG NPM_VERSION

WORKDIR /app

ENV BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=development \
    PLYWO_EXECUTOR_CAPABILITIES_JSON="{\"runtimes\":{\"ruby\":\"${RUBY_VERSION}\",\"node\":\"${NODE_VERSION}\"},\"package_managers\":{\"npm\":\"${NPM_VERSION}\"}}"

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential \
      git \
      libpq-dev \
      libsqlite3-dev \
      pkg-config && \
    rm -rf /var/lib/apt/lists/*

COPY --from=node_runtime /usr/local/bin/node /usr/local/bin/node
COPY --from=node_runtime /usr/local/bin/npm /usr/local/bin/npm
COPY --from=node_runtime /usr/local/bin/npx /usr/local/bin/npx
COPY --from=node_runtime /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm

RUN test "$(node --version)" = "v${NODE_VERSION}" && \
    test "$(npm --version)" = "${NPM_VERSION}"

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

ENV RAILS_ENV=production \
    RAILS_LOG_TO_STDOUT=1

EXPOSE 3000

CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
