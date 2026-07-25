class PushController < ApplicationController
  # The VAPID public key the browser needs to create a push subscription.
  def key
    render json: { key: Push.public_key }
  end

  # Store a browser's push subscription so the box can notify it later.
  def subscribe
    Push.subscribe(subscription_params)
    head :created
  end

  private

  def subscription_params
    params.require(:subscription)
          .permit(:endpoint, keys: %i[p256dh auth])
          .to_h.deep_stringify_keys
  end
end
