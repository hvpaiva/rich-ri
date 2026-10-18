FROM docker.io/library/ruby:4.0.7-slim-trixie@sha256:ba6a00593739f9cb66de80ad2e395a93a52a13635867ee32918ba0ec083b1ff6

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
      bash bash-completion zsh fish build-essential libyaml-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY Gemfile Gemfile.lock rich-ri.gemspec ./
COPY lib/rich_ri/version.rb lib/rich_ri/version.rb
ENV BUNDLE_FROZEN=true BUNDLE_APP_CONFIG=/tmp/bundle-config
RUN gem install bundler --no-document --version "$(ruby -e 'puts File.read("Gemfile.lock").split("BUNDLED WITH").last.strip')" \
    && bundle install --quiet

COPY lib lib
COPY completions completions
COPY test test

ENV HOME=/tmp RICH_RI_REQUIRE_SHELLS=1
USER 65532:65532
CMD ["bundle", "exec", "ruby", "-Ilib", "-Itest", "test/shell_test.rb"]
