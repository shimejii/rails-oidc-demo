class SocialUser < ApplicationRecord
  belongs_to :user

  # OIDC: iss(発行者) と sub(IdP内の一意ID) は本人特定に必須
  validates :iss, presence: true
  # (iss, sub) のペアで一意（DB の複合ユニークインデックスと対応）
  validates :sub, presence: true, uniqueness: { scope: :iss }
end
