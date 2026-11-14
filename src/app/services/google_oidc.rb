require "net/http"
require "json"
require "jwt"
require "base64"
require "digest"
require "securerandom"

# Google の OIDC（OpenID Connect）処理をまとめたサービスクラス。
# 認可コードフローのうち「トークン交換」と「ID トークン検証」を担う。
#
# 設計方針:
#   - エンドポイント URL はハードコードせず、OIDC Discovery
#     （/.well-known/openid-configuration）から取得する。
#   - Discovery と JWKS（公開鍵）は変化が少ないため Rails.cache でキャッシュする。
#   - ID トークン（JWT）の署名検証は自前実装せず jwt gem に任せる（暗号処理は実績ある
#     ライブラリを使うのが安全）。検証ロジック（iss/aud/exp/nonce）は自分で指定する。
class GoogleOidc
  DISCOVERY_URL = "https://accounts.google.com/.well-known/openid-configuration".freeze
  ISSUER        = "https://accounts.google.com".freeze

  class VerificationError < StandardError; end

  # PKCE (RFC 7636): 認可コードの横取り対策。
  # code_verifier は推測不能なランダム文字列（43〜128 文字の URL セーフ文字）。
  def self.generate_code_verifier
    SecureRandom.urlsafe_base64(64) # 86 文字
  end

  # code_challenge = BASE64URL(SHA256(code_verifier))（パディングなし）。
  # 認可リクエストにはこのハッシュだけを載せ、verifier 本体はトークン交換まで秘匿する。
  def self.code_challenge_for(code_verifier)
    Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false)
  end

  def initialize
    # 認証情報は環境変数から取得する（.env や本番のシークレット管理から注入）。
    # 未設定ならすぐ分かるよう fetch で例外にする。
    @client_id     = ENV.fetch("GOOGLE_CLIENT_ID")
    @client_secret = ENV.fetch("GOOGLE_CLIENT_SECRET")
    @redirect_uri  = ENV.fetch("GOOGLE_REDIRECT_URI")
  end

  # 認可コードをトークン群（id_token / access_token など）に交換する。
  # RP(サーバー) → Google のトークンエンドポイントへの POST。ブラウザは介さない。
  # code_verifier を送ると、Google は認可リクエスト時の code_challenge と照合し、
  # 一致しなければ invalid_grant で拒否する。
  def exchange_code(code, code_verifier:)
    response = post_form(discovery.fetch("token_endpoint"), {
      code:          code,
      client_id:     @client_id,
      client_secret: @client_secret,
      redirect_uri:  @redirect_uri,
      grant_type:    "authorization_code",
      code_verifier: code_verifier
    })

    raise VerificationError, "トークン交換に失敗しました: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  # ID トークン（JWT）を検証し、クレーム（本人情報）を返す。
  # 署名(RS256) / iss / aud / exp を jwt gem で検証し、nonce は自前で突き合わせる。
  def verify_id_token(id_token, expected_nonce:)
    payload, _header = JWT.decode(
      id_token,
      nil,
      true, # 署名検証を行う
      algorithms: ["RS256"],
      jwks:       jwks_loader,
      iss:        ISSUER,
      verify_iss: true,
      aud:        @client_id,
      verify_aud: true,
      verify_expiration: true
    )

    # nonce 検証（リプレイ対策）: 認可リクエスト時に送った値と一致するか
    unless payload["nonce"].present? && payload["nonce"] == expected_nonce
      raise VerificationError, "nonce が一致しません"
    end

    payload
  rescue JWT::DecodeError => e
    raise VerificationError, "ID トークンの検証に失敗しました: #{e.message}"
  end

  private

  # OIDC Discovery ドキュメント（エンドポイント一覧）を取得・キャッシュする。
  def discovery
    @discovery ||= Rails.cache.fetch("google_oidc:discovery", expires_in: 1.hour) do
      JSON.parse(get(DISCOVERY_URL).body)
    end
  end

  # JWKS（公開鍵）を取得する proc を返す。jwt gem が署名検証時に kid で鍵を引く。
  # force_refresh 時は鍵の再取得を行う（鍵ローテーションに追従）。
  def jwks_loader
    ->(options) do
      jwks_uri = discovery.fetch("jwks_uri")
      cache_key = "google_oidc:jwks"
      Rails.cache.delete(cache_key) if options[:invalidate]
      jwks = Rails.cache.fetch(cache_key, expires_in: 1.hour) do
        JSON.parse(get(jwks_uri).body)
      end
      JWT::JWK::Set.new(jwks)
    end
  end

  def get(url)
    Net::HTTP.get_response(URI(url))
  end

  def post_form(url, params)
    uri = URI(url)
    Net::HTTP.post_form(uri, params)
  end
end
