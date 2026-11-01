# syntax=docker/dockerfile:1

# ============================================================
# Ruby on Rails 開発環境 (Debian系 / slim ベース)
# ============================================================
# 公式 ruby イメージの slim タグは Debian (bookworm) ベース。
# 軽量ながら apt でビルドツールを追加できるため学習用途に扱いやすい。
# ------------------------------------------------------------

ARG RUBY_VERSION=3.4
FROM ruby:${RUBY_VERSION}-slim-bookworm

# --- ロケール / タイムゾーン -------------------------------
# 日本語・JST を扱えるように設定（学習時のログやDB確認で便利）
ENV LANG=C.UTF-8 \
    TZ=Asia/Tokyo

# --- Rails 推奨の構成要素をインストール --------------------
# build-essential : ネイティブ拡張gem(nokogiri等)のビルドに必要
# libpq-dev       : PostgreSQL 用クライアントライブラリ
# libvips         : Active Storage の画像変換 (Rails 推奨)
# git             : bundler の git ソース gem 取得に必要
# curl / gnupg    : Node.js リポジトリ追加などに使用
# pkg-config      : ネイティブ拡張のビルド補助
# vim             : credentials:edit などコンテナ内での編集用エディタ
# --------------------------------------------------------
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      build-essential \
      git \
      curl \
      gnupg \
      pkg-config \
      libpq-dev \
      libyaml-dev \
      libvips \
      postgresql-client \
      ca-certificates \
      vim && \
    rm -rf /var/lib/apt/lists/*

# --- Node.js & Yarn ----------------------------------------
# importmap 中心なら必須ではないが、jsbundling/cssbundling を
# 使う構成にも対応できるよう LTS を入れておく。
ARG NODE_MAJOR=22
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    npm install -g yarn && \
    rm -rf /var/lib/apt/lists/*

# --- アプリケーションディレクトリ ---------------------------
# ホスト側は リポジトリ直下の src/ に Rails アプリ本体を置く構成。
# （Docker 関連ファイルはリポジトリ直下、Rails 本体は src/ に分離）
# ※ Rails 内部の app/ ディレクトリと紛らわしくないよう src/ を採用。
# コンテナ内の作業ディレクトリは /app とする。
WORKDIR /app

# --- bundler の設定 ----------------------------------------
# gem をイメージ内の bundle ディレクトリに閉じ込め、ホストと分離する。
# bundle の実行ファイル置き場(bin)を PATH に通し、rails 等を直接叩けるようにする。
ENV BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3

# --- 依存関係を先にインストール（レイヤーキャッシュ活用）----
# src/ 内の Gemfile が存在する場合のみ bundle install を実行。
# 空（これから rails new する段階）でもビルドできるようフォールバックする。
COPY src/Gemfile* ./
RUN if [ -f Gemfile ]; then bundle install; else gem install rails; fi

# --- アプリ本体をコピー ------------------------------------
# ホストの src/ の中身を、コンテナの /app 直下へ配置する。
COPY src/ ./

# --- ポート公開 --------------------------------------------
EXPOSE 3000

# --- 起動コマンド ------------------------------------------
# 0.0.0.0 bind でコンテナ外（ホスト）からアクセス可能にする
CMD ["rails", "server", "-b", "0.0.0.0", "-p", "3000"]
