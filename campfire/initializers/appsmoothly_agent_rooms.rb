# Let a bot hold a conversation in a room that is not a private DM.
#
# Upstream, Campfire delivers a message to a bot in exactly two cases: the room
# is a DIRECT room, or the bot was @-mentioned. That makes a one-to-one DM the
# only place a bot can talk without being tagged every time -- which rules out a
# room a colleague can read, and rules out one room per feature.
#
# Memberships already carry the right idea. `involvement` is per (room, member)
# and says whether that member wants *everything* or only *mentions*. This
# widens the bot rule to honour it: an open room whose bot membership is
# `everything` behaves like a direct room, and every other room is untouched.
#
# Deliberately additive -- a new file, no upstream file edited -- so
# `campfire-update`'s `git merge --ff-only` can never conflict with it.
# `appsmoothly-install` copies it into the checkout before the image is built.

Rails.application.config.to_prepare do
  MessagesController.class_eval do
    private

    def bots_eligible_for_webhook
      return @room.users.active_bots if @room.direct?

      ids = @message.mentionees.active_bots.ids |
            @room.memberships.where(involvement: :everything).pluck(:user_id)
      User.active_bots.where(id: ids)
    end
  end
end
