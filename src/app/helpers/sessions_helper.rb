module SessionsHelper
  # 渡されたユーザーでログインする。
  # 固定化攻撃対策として reset_session で先にセッションを作り直してから、
  # 新しいセッションに user_id を入れ直す（順番が重要）。
  def log_in(user)
    reset_session
    session[:user_id] = user.id
    @current_user = user
  end

  # 現在ログイン中のユーザーを返す（いなければ nil）。
  # session[:user_id] からアプリ内ユーザーを復元する。
  def current_user
    return @current_user if defined?(@current_user) && @current_user

    if (user_id = session[:user_id])
      @current_user = User.find_by(id: user_id)
    end
  end

  # ログインしているかどうか
  def logged_in?
    current_user.present?
  end

  # ログアウトする。セッションを破棄して current_user をクリア。
  def log_out
    reset_session
    @current_user = nil
  end
end
