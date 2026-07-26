# Tells the attached browser to put one of claude's pages on screen. The signed
# token is the capability, same as TerminalChannel — anyone who can drive the
# terminal can already be shown a page by it.
class UiChannel < ApplicationCable::Channel
  def subscribed
    Factory.verifier.verify(params[:token].to_s)
    stream_from Ask::STREAM
    # Then catch up: a phone that was asleep when the question was asked has to
    # find it waiting when it wakes, or the push notification leads to an empty
    # screen. Same shape as a live broadcast, so the page handles both alike.
    Ask.pending.each { |prompt| transmit(prompt) }
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    reject
  end
end
