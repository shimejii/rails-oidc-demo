# Rails 学習アウトプット — Google OIDC サインインの自前実装

Rails Tutorial 完走後の学習アウトプットです。
認証ライブラリ（omniauth 等）に頼らず、**Google アカウントによる OIDC（OpenID Connect）サインインを認可コードフローから自前実装**した Rails アプリです。開発環境は Docker で構築しています。

## 目的
- OIDC 認可フローを実装し、理解を深める
- Rails Tutorial 完走後、ログイン機構・テーブル CRUD を再現して知識を定着させる

## 利用技術
- OS
    - Debian 系（`ruby:3.4-slim-bookworm` ベース）
- 言語・フレームワーク
    - Ruby 3.4
    - Rails 8.1
- アプリケーションサーバー
    - Puma
- データベース
    - PostgreSQL 17
- 認証
    - Google OIDC（認可コードフロー）を自前実装
    - ID トークンの署名検証のみ `jwt` gem を利用
- コンテナ
    - Docker / Docker Compose

## 設計のポイント
- **認証情報は User に持たせない**
    - ログイン情報は `SocialUser`（OIDC の `iss` / `sub`）に分離し、User は `name` のみ保持
- **ユーザーは初回サインイン時に自動作成**
    - OIDC 前提のため手動登録フォームは持たず、`(iss, sub)` を元に User と SocialUser を同時作成
- **秘密情報は環境変数で管理**
    - `client_secret` 等は `.env`（Git 管理外）から注入し、ソースにもリポジトリにも含めない

## セキュリティ対策

### state の利用
- クライアントが `state`（ランダム値）を生成してセッションに保存し、認可エンドポイントへ渡す
- クライアントは認可コード受領時（コールバック）に、受け取った `state` がセッションの値と一致するか確認する
- → **CSRF 対策**。攻撃者が用意した認可コードを、被害者のブラウザに挿入（コールバック）させることを防ぐ

### PKCE の利用
- クライアントが `code_verifier`（ランダム値）を生成してセッションに保存する
- クライアントは `code_challenge_method`（`S256`）で `code_verifier` をハッシュ化（SHA-256 → BASE64URL）した `code_challenge` を、認可エンドポイントへ渡す
- クライアントは認可コード受領後、`code_verifier` をトークンエンドポイントへ渡す
- 認可サーバー（Google）は、以前受領した `code_challenge_method` で `code_verifier` をハッシュ化し、以前受領した `code_challenge` と一致するか確認する。不一致なら `invalid_grant` で拒否する
- → **認可コードの横取り防止**。認可リクエストにはハッシュ（`code_challenge`）しか載らないため、認可コードを盗んだ攻撃者は `code_verifier` を作れず、トークンに交換できない

### その他
- **nonce**: ID トークン内の `nonce` が、認可リクエスト時にセッションへ保存した値と一致するか検証する（リプレイ対策）
- **ID トークンの検証**: 署名（Google の公開鍵 / JWKS）・`iss`・`aud`・`exp` を検証する
- **reset_session**: ログイン時にセッションを作り直す（セッション固定化対策）
- **使い捨て**: `state` / `nonce` / `code_verifier` は、コールバックに入った時点でセッションから削除する

## ディレクトリ構成
```text
demo/
├── Dockerfile            # Rails 開発用イメージ (Debian slim ベース)
├── docker-compose.yml    # web(Rails) + db(PostgreSQL) をまとめて起動
├── .env.example          # 環境変数のサンプル（実値は .env に記入 / .env は Git 管理外）
├── .gitignore
├── README.md
└── src/                  # Rails アプリ本体（app/ と紛らわしくないよう src/ に配置）
    ├── app/
    │   ├── controllers/
    │   │   └── sessions_controller.rb   # OIDC 認可コードフローの制御
    │   ├── services/
    │   │   └── google_oidc.rb           # トークン交換・ID トークン検証
    │   ├── helpers/
    │   │   └── sessions_helper.rb       # log_in / current_user / log_out
    │   └── models/
    │       ├── user.rb                  # name のみ（認証情報は持たない）
    │       ├── micropost.rb             # message / user_id
    │       └── social_user.rb           # iss / sub / email / user_id
    └── config/
        ├── routes.rb
        └── database.yml                 # 環境変数で db コンテナに接続
```

## 起動方法
### 1. Google OAuth クライアントを用意（初回のみ）
- Google Cloud Console で OAuth クライアント（ウェブアプリケーション）を作成する
- 承認済みリダイレクト URI に `http://localhost:3000/auth/google/callback` を登録する
- 発行された クライアント ID / クライアントシークレット を控える

### 2. 環境変数を設定
`.env.example` をコピーして `.env` を作成し、取得した値を記入する。

```bash
cp .env.example .env
# .env を編集:
#   GOOGLE_CLIENT_ID=...
#   GOOGLE_CLIENT_SECRET=...
#   GOOGLE_REDIRECT_URI=http://localhost:3000/auth/google/callback
```

### 3. ビルドとデータベース作成
```bash
docker compose build
docker compose run --rm web bin/rails db:create db:migrate
```

### 4. 起動
```bash
docker compose up
```

ブラウザで http://localhost:3000 を開き、「サインイン」から Google ログインを試せる。

## URLs

### 本アプリのエンドポイント
| メソッド | パス | 役割 |
| --- | --- | --- |
| GET | `/signin` | サインイン画面（Google ログインボタン） |
| GET | `/auth/google` | 認可リクエストの開始（Google へリダイレクト） |
| GET | `/auth/google/callback` | Google からのコールバック（認可コードを受け取る） |
| DELETE | `/signout` | サインアウト |

`/auth/google/callback` は、Google Cloud Console の「承認済みのリダイレクト URI」に登録した値と完全一致させる必要がある。

### Google のエンドポイント
項番（E1〜E4）は、後述のシーケンス図のメッセージに付けた項番と対応している。項番は、認証フローの中で呼ばれる順に振っている。

| 項番 | 名前 | URL | 用途 | シーケンス図での対応 |
| --- | --- | --- | --- | --- |
| E1 | 認可エンドポイント | `https://accounts.google.com/o/oauth2/v2/auth` | 認可リクエストの送り先 | クライアントが `302 Location: Google 認可エンドポイント [E1]` でブラウザに送り先として指示し、ブラウザが `GET 認可エンドポイント [E1]` で Google にアクセスする |
| E2 | Discovery | `https://accounts.google.com/.well-known/openid-configuration` | 各エンドポイントの URL を取得する | クライアントが `GET /.well-known/openid-configuration (Discovery) [E2]` で Google に問い合わせる（図 1）。図 3 ではキャッシュを使うので通信しない |
| E3 | トークンエンドポイント | `https://oauth2.googleapis.com/token` | 認可コードをトークンに交換する | クライアントが `POST token [E3]` で Google に送る（図 1・図 3）。図 5 では攻撃者が同じエンドポイントに送る |
| E4 | JWKS | `https://www.googleapis.com/oauth2/v3/certs` | ID トークンの署名検証に使う公開鍵 | クライアントが `GET JWKS (公開鍵) [E4]` で Google から取得する（図 1）。図 3 ではキャッシュを使うので通信しない |

E3 と E4 の URL は、E2 の Discovery ドキュメント（`token_endpoint` / `jwks_uri`）から取得して使う。E1 のみ、コード内の定数（`GOOGLE_AUTH_ENDPOINT`）として持っている。

### 認証 URI パラメータ
本アプリが `/auth/google` で組み立てる認可リクエスト URL（E1 宛て）の主なクエリパラメータ。

| パラメータ | 必須 | 説明 |
| --- | --- | --- |
| `client_id` | 必須 | Cloud Console で取得したクライアント ID |
| `redirect_uri` | 必須 | Google がレスポンスを返す先 |
| `response_type` | 必須 | `code` を指定すると認可コードフローになる |
| `scope` | 必須 | 先頭は `openid` にし、`profile` と `email` のどちらか、または両方を続ける（スペース区切り） |
| `nonce` | 必須 | リプレイ対策のランダム値。ID トークンに埋め込まれて返る |
| `state` | 任意（強く推奨） | リクエストとレスポンスの往復で、そのまま返される値。リダイレクト先は推測できるため、自分が開始した認証のレスポンスかを `state` で検証し、CSRF を防ぐ |
| `code_challenge` | 任意（PKCE） | PKCE のチャレンジ。`code_verifier` を `code_challenge_method` でハッシュ化した値 |
| `code_challenge_method` | 任意（PKCE） | `code_challenge` の生成方法 |

- `code_challenge` と `code_challenge_method` は、上記の Google ドキュメントの表には載っていない。RFC 7636（PKCE）で定義された標準のパラメータで、Discovery ドキュメントの `code_challenge_methods_supported` に `plain` と `S256` が含まれることを確認している。
- 実際に組み立てられる URL では、Rails の `to_query` によりパラメータ名がアルファベット順に並ぶ。

```text
https://accounts.google.com/o/oauth2/v2/auth
  ?client_id=<CLIENT_ID>
  &code_challenge=<CODE_CHALLENGE>
  &code_challenge_method=S256
  &nonce=<NONCE>
  &redirect_uri=http%3A%2F%2Flocalhost%3A3000%2Fauth%2Fgoogle%2Fcallback
  &response_type=code
  &scope=openid+email+profile
  &state=<STATE>
```

### 出典
- Google for Developers「OpenID Connect」の「Authentication URI parameters」
  https://developers.google.com/identity/openid-connect/openid-connect?hl=ja#authenticationuriparameters

## シーケンス図
- エンティティ
    - **ブラウザ**: ユーザーの操作主体
    - **クライアント (本アプリ / RP)**: 認証を Google に委ね、結果を受け取る
    - **Google (OAuth 2.0 / OIDC サーバー)**: 認証・認可を行い、トークンと公開鍵を提供する

> 実装範囲は「認可リクエスト（state / nonce / PKCE の code_challenge 付き）→ 認可コード取得 →
> state 一致確認 → Discovery でエンドポイント取得 → トークンエンドポイントで（code_verifier を送って）
> `id_token` / `access_token` 取得 → JWKS で公開鍵を取得 → `id_token` の署名・クレーム検証 →
> ユーザー確定・ログイン」まで。トークン取得後、検証のために JWKS を取りに行く往復まで含む。
>
> 図中の ①②③ は「一致確認」の箇所を表す。① state 一致確認（本アプリ）、② PKCE 照合（Google）、
> ③ ID トークンの検証（署名・`iss`・`aud`・`exp`・nonce 一致確認。本アプリ）。

### 1. 認可フロー（認可成功）

```mermaid
sequenceDiagram
    participant B as ブラウザ
    participant C as クライアント(本アプリ)
    participant G as Google(OAuth2.0/OIDC)

    B->>C: GET /auth/google
    Note over C: state / nonce / code_verifier(PKCE) を生成しセッションに保存<br/>code_challenge = BASE64URL(SHA256(code_verifier))
    C-->>B: 302 Location: Google 認可エンドポイント [E1]<br/>(client_id, redirect_uri, scope=openid.., state, nonce,<br/>code_challenge, code_challenge_method=S256)

    B->>G: GET 認可エンドポイント [E1]
    Note over G: code_challenge を認可コードに紐付けて保持
    G-->>B: ログイン・同意画面
    B->>G: 認証・同意
    G-->>B: 302 Location: /auth/google/callback?code=..&state=..

    B->>C: GET /auth/google/callback?code=..&state=..
    Note over C: セッションから state / nonce / code_verifier を取り出して削除（使い捨て）
    Note over C: ① state 一致確認（params[:state] == セッションの state）<br/>一致 → 続行 / 不一致 → 拒否（図 4）

    C->>G: GET /.well-known/openid-configuration (Discovery) [E2]
    G-->>C: 各エンドポイント URL
    C->>G: POST token [E3] (code, code_verifier, client_id, client_secret,<br/>redirect_uri, grant_type)
    Note over G: ② PKCE 照合: SHA256(code_verifier) == 保持している code_challenge ?<br/>一致 → トークン発行 / 不一致 → 400 invalid_grant（図 5）
    G-->>C: 200 { id_token, access_token, .. }
    C->>G: GET JWKS (公開鍵) [E4]
    G-->>C: 公開鍵セット

    Note over C: ③ id_token 検証（署名 / iss / aud / exp / nonce 一致確認）
    Note over C: (iss, sub) で検索 → 未登録なら User + SocialUser 作成
    Note over C: reset_session → user_id 保存（ログイン確立）
    C-->>B: 302 Location: /（サインイン完了）
```

### 2. 認可フロー（認可拒否）

ユーザーが同意画面でキャンセルした場合。Google は `error` を付けてコールバックへ戻す。

```mermaid
sequenceDiagram
    participant B as ブラウザ
    participant C as クライアント(本アプリ)
    participant G as Google(OAuth2.0/OIDC)

    B->>C: GET /auth/google
    Note over C: state / nonce / code_verifier(PKCE) を生成しセッションに保存
    C-->>B: 302 Location: Google 認可エンドポイント [E1]

    B->>G: GET 認可エンドポイント [E1]
    G-->>B: ログイン・同意画面
    B->>G: 同意をキャンセル（拒否）
    G-->>B: 302 Location: /auth/google/callback?error=access_denied&state=..

    B->>C: GET /auth/google/callback?error=access_denied&state=..
    Note over C: セッションの state / nonce / code_verifier を取り出して削除（使い捨て）
    Note over C: params[:error] を検知 → ここで終了<br/>（error 判定は state 検証より先。認可コードは無いのでトークン交換も行わない）
    C-->>B: 302 Location: /signin（「サインインがキャンセルされました」）
```

### 3. 認可フロー（認可成功・2 回目以降）

2 回目以降は、(iss, sub) に対応する `SocialUser` が既に存在するためユーザーは作成されない。
また Discovery / JWKS は `Rails.cache` にキャッシュ済みのため、通信を省略できる。
（Google 側も、ログイン済みなら同意画面をスキップすることが多い）

```mermaid
sequenceDiagram
    participant B as ブラウザ
    participant C as クライアント(本アプリ)
    participant G as Google(OAuth2.0/OIDC)

    B->>C: GET /auth/google
    Note over C: state / nonce / code_verifier(PKCE) を生成しセッションに保存<br/>code_challenge = BASE64URL(SHA256(code_verifier))
    C-->>B: 302 Location: Google 認可エンドポイント [E1]<br/>(.., state, nonce, code_challenge, code_challenge_method=S256)

    B->>G: GET 認可エンドポイント [E1]
    Note over G: 同意済みなら同意画面をスキップ
    G-->>B: 302 Location: /auth/google/callback?code=..&state=..

    B->>C: GET /auth/google/callback?code=..&state=..
    Note over C: セッションから state / nonce / code_verifier を取り出して削除（使い捨て）
    Note over C: ① state 一致確認

    Note over C,G: Discovery [E2] / JWKS [E4] はキャッシュ利用（通信省略）
    C->>G: POST token [E3] (code, code_verifier, client_id, client_secret, ..)
    Note over G: ② PKCE 照合: SHA256(code_verifier) == code_challenge
    G-->>C: 200 { id_token, access_token, .. }

    Note over C: ③ id_token 検証（署名 / iss / aud / exp / nonce 一致確認）
    Note over C: (iss, sub) で既存 SocialUser を発見 → User を特定（作成しない）
    Note over C: reset_session → user_id 保存（ログイン確立）
    C-->>B: 302 Location: /（サインイン完了）
```

### 4. 認可フロー（state 不一致で拒否）

コールバックの `state` が、認可リクエスト時にセッションへ保存した値と一致しない場合。
他者が用意した認可コードを、被害者のブラウザで強制的にコールバックさせる攻撃（ログイン CSRF）や、
セッションの失効・別ブラウザからのアクセスなどで起きる。**トークン交換には進まない**。

```mermaid
sequenceDiagram
    participant B as ブラウザ
    participant C as クライアント(本アプリ)
    participant G as Google(OAuth2.0/OIDC)

    B->>C: GET /auth/google
    Note over C: state=S1 / nonce / code_verifier を生成しセッションに保存
    C-->>B: 302 Location: Google 認可エンドポイント [E1] (state=S1, ..)

    Note over B,G: （通常の認可フロー。または攻撃者が別経路で用意した URL）
    B->>C: GET /auth/google/callback?code=..&state=S2
    Note over C: セッションから state / nonce / code_verifier を取り出して削除（使い捨て）
    Note over C: ① state 一致確認: S2 == S1 ?<br/>不一致（またはセッションに state なし）→ 拒否
    Note over C: トークン交換・ID トークン検証は行わない
    C-->>B: 302 Location: /signin（「不正なリクエストです（state 不一致）」）
```

### 5. 認可フロー（PKCE により認可コードの横取りを防ぐ）

ブラウザ経由で渡る認可コードが、攻撃者に横取りされた場合。
認可リクエストに載っているのは `code_challenge`（ハッシュ）だけで、元の `code_verifier` は本アプリのセッション内にしかない。
攻撃者は verifier を作れないため、横取りした認可コードをトークンに交換できない。**トークンは発行されない**。

```mermaid
sequenceDiagram
    participant B as ブラウザ
    participant C as クライアント(本アプリ)
    participant G as Google(OAuth2.0/OIDC)
    participant A as 攻撃者

    B->>C: GET /auth/google
    Note over C: code_verifier(V1) を生成しセッションに保存<br/>code_challenge(H1) = BASE64URL(SHA256(V1))
    C-->>B: 302 Location: Google 認可エンドポイント [E1] (code_challenge=H1, ..)
    B->>G: GET 認可エンドポイント [E1]
    Note over G: 認可コードに code_challenge=H1 を紐付けて保持
    G-->>B: 302 Location: /auth/google/callback?code=..&state=..

    Note over B,A: ブラウザ経路で認可コードが漏れる（ログ・履歴・悪意あるアプリ等）
    B-->>A: 認可コード（V1 は含まれない）

    A->>G: POST token [E3] (横取りした code, code_verifier=推測した値)
    Note over G: PKCE 照合: SHA256(推測した値) == H1 ?<br/>不一致（攻撃者は V1 を知らない）→ 拒否
    G-->>A: 400 { "error": "invalid_grant" }
```

なお本アプリは `client_secret` もサーバー内でのみ保持しているため、攻撃者はこれも持たない。PKCE はそれとは独立した追加の防御になる。
