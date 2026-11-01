class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # セッション関連のヘルパーをコントローラでも使えるように取り込む
  include SessionsHelper
  # current_user / logged_in? をビューからも呼べるように公開する
  helper_method :current_user, :logged_in?
end
