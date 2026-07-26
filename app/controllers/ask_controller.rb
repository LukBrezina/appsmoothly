class AskController < ApplicationController
  # The browser posts the filled-in form back from inside the pop-up's iframe,
  # and bin/mcp-ui drives the rest over loopback. Both are same-origin behind
  # Caddy/Authelia — the same boundary the terminal itself relies on — and a
  # session token would only get in the way of a page claude wrote by hand.
  skip_forgery_protection

  # --- called by bin/mcp-ui (loopback) --------------------------------------

  # Put a page in front of the user. Returns the id to poll for their answer.
  def create
    id = Ask.open!(path: params.require(:path), title: params[:title],
                   wait: params[:wait] != false)
    Push.notify_asked!(params[:title]) # they may not be looking at the terminal
    render json: { id: id }
  end

  # Long-poll: hold the request open until the user answers, so the tool call
  # claude is sitting in returns the moment they tap, not seconds later.
  def result
    prompt = Ask.find(params[:id]) or return head :not_found
    deadline = Time.now + params.fetch(:timeout, 25).to_i.clamp(0, 60)
    until Ask.answered?(prompt) || Time.now >= deadline
      sleep 0.25
      prompt = Ask.find(params[:id]) or return head :not_found
    end
    render json: prompt.slice("id", "answer", "dismissed", "answered_at")
                       .merge("status" => Ask.answered?(prompt) ? "answered" : "waiting")
  end

  # Buzz their phone about something that isn't a question.
  def notify
    Push.broadcast(title: params[:title].presence || "Claude", body: params.require(:body))
    head :ok
  end

  # --- called by the browser ------------------------------------------------

  # The page itself, served into the pop-up's iframe with the reply shim
  # appended, so claude only ever has to write a plain <form>.
  def show
    prompt = Ask.find(params[:id]) or return head :not_found
    html = Ask.page_for(prompt) or return head :not_found
    render html: inject_shim(html, prompt).html_safe, layout: false # rubocop:disable Rails/OutputSafety
  end

  # Their answer. `answer` is whatever the form held, shaped by the shim.
  def answer
    return head :not_found unless Ask.answer!(params[:id], answer_value,
                                              dismissed: params[:dismissed].present?)
    head :ok
  end

  private

  # Whatever shape claude's form had — its field names are its own invention, so
  # there is nothing to whitelist against. Flattened to a plain Hash because
  # Parameters serialises to its own inspect output, and this ends up as JSON in
  # front of claude.
  def answer_value
    raw = params[:answer]
    raw.is_a?(ActionController::Parameters) ? raw.permit!.to_h : raw
  end

  # Everything the page needs to talk back, injected rather than required of
  # claude: submitting any form posts it here and closes the pop-up.
  def inject_shim(html, prompt)
    shim = ApplicationController.render(partial: "ask/shim", locals: { id: prompt["id"] })
    html.sub(%r{</body>}i) { shim + "</body>" }.then { |out| out == html ? html + shim : out }
  end
end
