# The bot and its welcome must exist the moment first-run completes -- the
# owner's first sight of All Talk is the product's first impression, and a
# 30-second timer outside the container cannot beat the redirect. So the bot
# is created HERE, synchronously, inside FirstRun.create!; the timer-based
# campfire-bot-init still runs afterwards for the slower wiring (bridge
# config, avatar, branding) and finds the bot already present.
#
# Needs one read-only bind mount (campfire.service provides it):
#   /appsmoothly-state  -> /var/lib/campfire-init   (bridge-secret)
# A missing file degrades gracefully to the old timer-only behavior.
module AppsmoothlyFirstRunWelcome
  BRIDGE_SECRET_FILE = "/appsmoothly-state/bridge-secret"
  BRIDGE_GATEWAY     = "172.17.0.1"

  def create!(user_params)
    administrator = super
    begin
      secret = File.read(BRIDGE_SECRET_FILE).strip rescue nil

      bot = User.active_bots.order(:id).first
      if bot.nil? && secret.present?
        bot = User.create_bot!(
          name: "AppSmoothly", email_address: "claude@bot.local",
          password: SecureRandom.hex(16),
          webhook_url: "http://#{BRIDGE_GATEWAY}:4488/hook/#{secret}")
      end

      room = Room.where(name: FirstRun::FIRST_ROOM_NAME).order(:id).first
      if bot && room
        room.memberships.grant_to [ bot ] unless room.memberships.exists?(user_id: bot.id)
        room.memberships.where(user_id: bot.id).update_all(involvement: "everything")
        body =
          "Welcome. One project, one machine — you talk here, I build.<br>" \
          "<strong>To start, paste the GitHub repo URL.</strong><br>" \
          "Secrets go through one-time links, never through chat. " \
          "You get a preview URL when the app runs. After that, ask for features."
        Current.set(user: bot) do
          room.messages.create!(creator: bot, body: body)
        end
      end
    rescue => e
      Rails.logger.error("appsmoothly first-run welcome failed: #{e.class}: #{e.message}")
    end
    administrator
  end
end

Rails.application.config.to_prepare do
  FirstRun.singleton_class.prepend(AppsmoothlyFirstRunWelcome)
end
