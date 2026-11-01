class CreateSocialUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :social_users do |t|
      t.string :provider
      t.string :uid
      t.string :email
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
