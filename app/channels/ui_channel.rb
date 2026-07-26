# Tells the attached browser to put one of claude's pages on screen. The signed
# token is the capability, same as TerminalChannel — anyone who can drive the
# terminal can already be shown a page by it.
class UiChannel < ApplicationCable::Channel
  def subscribed
    Factory.verifier.verify(params[:token].to_s)
    stream_from Ask::STREAM
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    reject
  end
end
