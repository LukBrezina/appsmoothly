# The factory keeps no state any more: tmux says whether claude is running, the
# filesystem holds the app, and claude owns everything else. Existing boxes drop
# their two tables here.
class DropAppTables < ActiveRecord::Migration[8.1]
  def up
    drop_table :sessions, if_exists: true
    drop_table :apps, if_exists: true
  end

  def down = raise(ActiveRecord::IrreversibleMigration)
end
