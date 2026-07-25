class PwaController < ApplicationController
  # The web-app manifest — makes "Add to Home Screen" install a real app, which
  # is what iOS requires before it will show any web notification.
  def manifest
    render template: "pwa/manifest", formats: :json, handlers: :erb,
           content_type: "application/manifest+json", layout: false
  end

  # Served at /service-worker.js (root scope) so it can receive Web Push and show
  # the notification even while the app is backgrounded.
  def service_worker
    response.set_header("Service-Worker-Allowed", "/")
    render template: "pwa/service-worker", formats: :js, handlers: :erb,
           content_type: "text/javascript", layout: false
  end

  private

  # Rails blocks non-XHR JavaScript GET responses (to stop <script> data theft),
  # which would also block a browser fetching the service worker. These two files
  # are static, public assets with no secrets, so opt them out.
  def verify_same_origin_request = nil
end
