class SessionsController < ApplicationController
  # GET /signin
  # サインイン画面（Google ログインボタンを表示）
  def new
  end

  # Google の認可エンドポイント（OIDC 仕様で定められた固定 URL）
  GOOGLE_AUTH_ENDPOINT = "https://accounts.google.com/o/oauth2/v2/auth".freeze

  # GET /auth/google
  # 認可リクエストを開始し、Google の認可エンドポイントへリダイレクトする。
  # CSRF 対策の state、リプレイ対策の nonce を生成してセッションに保存しておく
  # （コールバックで検証に使う）。
  def authorize
    session[:oauth_state] = SecureRandom.hex(16)
    session[:oidc_nonce]  = SecureRandom.hex(16)

    redirect_to build_google_authorization_url, allow_other_host: true
  end

  # GET /auth/google/callback
  # Google からのコールバック。認可コードを受け取り、本人を確定してログインする。
  def callback
    # ユーザーが同意をキャンセルした場合など（例: error=access_denied）
    if params[:error].present?
      return redirect_to signin_path, alert: "サインインがキャンセルされました。"
    end

    # 1. state 検証（CSRF 対策）: 送られてきた state が自分の発行値と一致するか
    unless params[:state].present? && params[:state] == session[:oauth_state]
      return redirect_to signin_path, alert: "不正なリクエストです（state 不一致）。"
    end

    oidc = GoogleOidc.new

    # 2. 認可コード → トークン交換（ID トークン取得）
    tokens = oidc.exchange_code(params[:code])

    # 3. ID トークン検証（署名 / iss / aud / exp / nonce）
    claims = oidc.verify_id_token(tokens["id_token"], expected_nonce: session[:oidc_nonce])

    # 4. 本人確定 → ユーザーを特定（いなければ新規作成）
    user = find_or_create_user_from(claims)

    # 5. ログイン（log_in 内で reset_session → user_id 投入。固定化対策）
    log_in(user)
    redirect_to root_path, notice: "サインインしました。"
  rescue GoogleOidc::VerificationError => e
    Rails.logger.warn("[OIDC] 検証失敗: #{e.message}")
    redirect_to signin_path, alert: "サインインに失敗しました。"
  end

  # DELETE /signout
  def destroy
    log_out
    redirect_to root_path, notice: "サインアウトしました。"
  end

  private

  # ID トークンのクレームから、アプリ内ユーザーを特定する。
  # (iss, sub) で SocialUser を検索し、未登録なら User ごと新規作成する
  # （OIDC 前提: ユーザーの手動作成はせず、初回サインイン時に自動作成）。
  def find_or_create_user_from(claims)
    iss   = claims["iss"]
    sub   = claims["sub"]
    email = claims["email"]
    name  = claims["name"].presence || email.presence || "名無しユーザー"

    social_user = SocialUser.find_by(iss: iss, sub: sub)
    return social_user.user if social_user

    # 未登録 → User と SocialUser をまとめて作成（途中失敗で片方だけ残さない）
    ActiveRecord::Base.transaction do
      user = User.create!(name: name)
      user.social_users.create!(iss: iss, sub: sub, email: email)
      user
    end
  end

  # Google 認可エンドポイントへ送る URL を組み立てる。
  # response_type=code の認可コードフロー。scope に openid を含めることで OIDC となり、
  # IDトークンが発行される。nonce は IDトークンに埋め込まれ、コールバックで突き合わせる。
  def build_google_authorization_url
    params = {
      client_id:     ENV.fetch("GOOGLE_CLIENT_ID"),
      redirect_uri:  ENV.fetch("GOOGLE_REDIRECT_URI"),
      response_type: "code",
      scope:         "openid email profile",
      state:         session[:oauth_state],
      nonce:         session[:oidc_nonce],
      prompt:        "select_account"
    }

    "#{GOOGLE_AUTH_ENDPOINT}?#{params.to_query}"
  end
end
