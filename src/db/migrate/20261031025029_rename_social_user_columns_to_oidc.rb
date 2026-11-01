class RenameSocialUserColumnsToOidc < ActiveRecord::Migration[8.1]
  def change
    # OIDC の用語に合わせてカラム名を変更
    #   provider -> iss (issuer: トークン発行者)
    #   uid      -> sub (subject: IdP 内のユーザー一意 ID)
    rename_column :social_users, :provider, :iss
    rename_column :social_users, :uid, :sub

    # iss / sub は本人特定に必須のため NOT NULL 制約を付与
    change_column_null :social_users, :iss, false
    change_column_null :social_users, :sub, false

    # (iss, sub) のペアで世界的に一意 → 複合ユニークインデックス
    # 同じ IdP の同じユーザーを二重登録しないことを DB レベルで保証する
    add_index :social_users, [:iss, :sub], unique: true,
              name: "index_social_users_on_iss_and_sub"
  end
end
