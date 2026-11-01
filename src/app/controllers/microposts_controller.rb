class MicropostsController < ApplicationController
  before_action :set_micropost, only: %i[show edit update destroy]

  # GET /microposts
  def index
    # 作成日時の新しい順に並べ、1ページ 20 件でページネーション
    @microposts = Micropost.order(created_at: :desc).page(params[:page]).per(20)
  end

  # GET /microposts/:id
  def show
  end

  # GET /microposts/new
  def new
    @micropost = Micropost.new
  end

  # GET /microposts/:id/edit
  def edit
  end

  # POST /microposts
  def create
    @micropost = Micropost.new(micropost_params)
    if @micropost.save
      redirect_to @micropost, notice: "Micropost を作成しました。"
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /microposts/:id
  def update
    if @micropost.update(micropost_params)
      redirect_to @micropost, notice: "Micropost を更新しました。"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /microposts/:id
  def destroy
    @micropost.destroy
    redirect_to microposts_path, notice: "Micropost を削除しました。"
  end

  private

  def set_micropost
    @micropost = Micropost.find(params[:id])
  end

  # Strong Parameters: 許可するカラムだけ受け取る
  # message と、所属ユーザーを指定する user_id を許可
  def micropost_params
    params.require(:micropost).permit(:message, :user_id)
  end
end
