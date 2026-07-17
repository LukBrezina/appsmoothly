class CreateSessions < ActiveRecord::Migration[8.1]
  def up
    create_table :sessions do |t|
      t.references :app, null: false, foreign_key: true
      t.string :name, null: false
      t.string :title
      t.timestamps
      t.index %i[app_id name], unique: true
    end

    # Sessions used to live only in tmux; adopt any worktrees that predate rows.
    Dir.glob(File.join(Factory.worktrees_dir, "*--*")).each do |dir|
      app_name, name = File.basename(dir).split("--", 2)
      app_id = select_value("SELECT id FROM apps WHERE name = #{quote(app_name)}")
      next unless app_id

      execute <<~SQL
        INSERT INTO sessions (app_id, name, title, created_at, updated_at)
        VALUES (#{app_id}, #{quote(name)}, #{quote(name.humanize)}, datetime('now'), datetime('now'))
      SQL
    end
  end

  def down = drop_table(:sessions)
end
