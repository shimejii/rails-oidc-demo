Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # User は OIDC 前提のため手動作成動線（new/create）を持たない。
  # さらに他ユーザーを一覧・検索させないため index も除外する。
  resources :users, except: %i[new create index]

  # Micropost は CRUD 全アクションを使用
  resources :microposts

  # --- 認証（OIDC 認可コードフロー）----------------------------
  # サインイン画面（Google ログインボタンを表示）
  get "signin", to: "sessions#new"
  # 認可リクエスト開始（Google へリダイレクト）
  get "auth/google", to: "sessions#authorize", as: :auth_google
  # Google からのコールバック（認可コードを受け取る）
  get "auth/google/callback", to: "sessions#callback"
  # サインアウト
  delete "signout", to: "sessions#destroy"

  # Defines the root path route ("/")
  root "microposts#index"
end
