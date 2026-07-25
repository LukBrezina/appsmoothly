require "pty"
require "io/console"
require "base64"

# Bridges a browser xterm to `tmux attach` over a PTY. The signed token IS the
# capability — it's minted by the session page and names the tmux session.
# Output is base64-encoded: PTY bytes aren't guaranteed valid UTF-8/JSON.
class TerminalChannel < ApplicationCable::Channel
  def subscribed
    tmux_name = Factory.verifier.verify(params[:token].to_s)
    @pty, @writer, @pid = PTY.spawn({ "TERM" => "xterm-256color" }, "tmux", "attach-session", "-t", tmux_name)
    Process.detach(@pid)
    @reader = Thread.new do
      loop do
        bytes = @pty.readpartial(4096)
        transmit Base64.strict_encode64(bytes)
        # BEL = claude finished a turn and wants you. Push off-thread so a slow
        # push service never stalls terminal output; Push debounces the rest.
        Thread.new { Push.notify_done! } if bytes.include?("\a")
      end
    rescue EOFError, Errno::EIO
      # tmux client exited (detach / kill-session) — browser side just goes quiet
    end
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    reject
  end

  def input(data)
    @writer&.write(data["data"])
  end

  def resize(data)
    @pty&.winsize = [data["rows"].to_i, data["cols"].to_i]
  end

  def unsubscribed
    @reader&.kill
    Process.kill("HUP", @pid) if @pid # detaches the tmux client; the session lives on
  rescue Errno::ESRCH
  ensure
    [@pty, @writer].each { |io| io.close rescue nil if io }
  end
end
