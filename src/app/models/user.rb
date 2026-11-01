class User < ApplicationRecord
  # 1(User) 対 多(Micropost)
  has_many :microposts, dependent: :destroy

  # 1(User) 対 多(SocialUser) … SNS 連携情報は SocialUser 側に持つ
  has_many :social_users, dependent: :destroy
end
