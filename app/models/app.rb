class App < ApplicationRecord
  AGENTS = %w[claude].freeze
  # "start" is the onboarding route; "factory" prefixes onboarding tmux sessions (factory--<name>)
  RESERVED_NAMES = %w[apps cable assets rails setup deploy restore new up start factory].freeze

  # Users type any title ("My new app"); the technical name (folders, web
  # address, tmux) is derived automatically.
  before_validation { self.name = title.parameterize if title.present? && name.blank? }

  # Set only while connecting an existing app by git address (not stored).
  attr_accessor :repo_url
  validates :repo_url, format: { with: %r{\A(https://|git@)[^\s']+\z}, message: "doesn't look like a git address" },
                       allow_blank: true

  validates :name, presence: { message: "needs at least a few letters or numbers" },
                   uniqueness: { message: "is too similar to an app you already have" },
                   format: { with: /\A\w+(?:-\w+)*\z/, message: "allows letters, digits, _ and single dashes" },
                   exclusion: { in: RESERVED_NAMES, message: "is reserved — pick another one" }
  validates :agent, inclusion: { in: AGENTS }
  validates :prod_server, format: { with: /\A[a-z0-9.-]+\z/i, message: "must be a tailscale name or IP" }, allow_blank: true
  validates :prod_host, format: { with: /\A[a-z0-9.-]+\z/i, message: "must be a hostname" }, allow_blank: true

  def to_param = name
  def display_name = title.presence || name
  def path = File.join(Factory.projects_dir, name)
  def ready? = File.directory?(File.join(path, ".git"))
  def sessions = Session.for(self)

  # production / backups readiness — kamal uses its local registry, no external creds
  def deployable? = ready? && prod_server.present? && prod_host.present?
  def backups_configured? = s3_bucket.present? && s3_access_key_id.present? && s3_secret_access_key.present?

  # Provisioned boxes (infra/) supply the bucket credentials via env, so backups
  # are on out of the box — no per-app setup, the columns stay a manual override.
  %w[s3_bucket s3_region s3_endpoint s3_access_key_id s3_secret_access_key].each do |column|
    define_method(column) { super().presence || ENV["RAF_#{column.upcase}"] }
  end

  def s3_region_or_default = s3_region.presence || "us-east-1"
  def s3_endpoint_or_default = s3_endpoint.presence || "https://s3.#{s3_region_or_default}.amazonaws.com"

  # env for the app itself (Active Storage in prod, serving pulled prod data in dev)
  def s3_env
    { "S3_BUCKET" => s3_bucket.to_s, "S3_REGION" => s3_region_or_default, "S3_ENDPOINT" => s3_endpoint.to_s,
      "S3_ACCESS_KEY_ID" => s3_access_key_id.to_s, "S3_SECRET_ACCESS_KEY" => s3_secret_access_key.to_s }
  end

  # env for litestream (replication accessory, restore, pull-prod-data)
  def litestream_env
    { "LITESTREAM_BUCKET" => s3_bucket.to_s, "LITESTREAM_REGION" => s3_region_or_default,
      "LITESTREAM_ENDPOINT" => s3_endpoint_or_default,
      "LITESTREAM_ACCESS_KEY_ID" => s3_access_key_id.to_s, "LITESTREAM_SECRET_ACCESS_KEY" => s3_secret_access_key.to_s }
  end
end
