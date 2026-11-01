class UsersController < ApplicationController
  before_action :set_user, only: %i[show edit update destroy]

  # 他ユーザーの一覧・検索をさせないため index は廃止（ルートも除外済み）。

  # GET /users/:id
  def show
    # このユーザーの投稿を、作成日時の新しい順・1ページ 20 件で取得
    @microposts = @user.microposts
                       .order(created_at: :desc)
                       .page(params[:page])
                       .per(20)
  end

  # OIDC 前提のため、ユーザーの手動作成動線（new/create）は無効化。
  # ユーザーは「ID トークン取得時にアプリ側に未登録なら自動作成」される想定で、
  # フォームから直接 new/create を呼ぶことはない。
  #
  # # GET /users/new
  # def new
  #   @user = User.new
  # end
  #
  # # POST /users
  # def create
  #   @user = User.new(user_params)
  #   if @user.save
  #     redirect_to @user, notice: "User を作成しました。"
  #   else
  #     render :new, status: :unprocessable_entity
  #   end
  # end

  # GET /users/:id/edit
  def edit
  end

  # PATCH/PUT /users/:id
  def update
    if @user.update(user_params)
      redirect_to @user, notice: "User を更新しました。"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /users/:id
  def destroy
    @user.destroy
    # users 一覧は廃止したため、トップ（microposts 一覧）へ戻す
    redirect_to root_path, notice: "User を削除しました。"
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  # Strong Parameters: 許可するカラムだけ受け取る
  def user_params
    params.require(:user).permit(:name)
  end
end
