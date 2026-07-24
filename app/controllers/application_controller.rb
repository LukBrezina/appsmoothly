class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # The terminal grants a real shell — this box binds to loopback (see
  # config/puma.rb) and is reached only from localhost (Caddy + Authelia in
  # front on a provisioned box), so the network itself is the boundary and no
  # in-app login is needed.
end
