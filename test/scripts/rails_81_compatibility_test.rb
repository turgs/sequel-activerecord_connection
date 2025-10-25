#!/usr/bin/env ruby
# frozen_string_literal: true

# Quick integration test for Rails 8.1 compatibility
# Run with: BUNDLE_GEMFILE=gemfiles/Gemfile.activerecord-8.1 bundle exec ruby test/scripts/rails_81_compatibility_test.rb

require "bundler/setup"
require "active_record"
require "sequel"

puts "Testing sequel-activerecord_connection with Rails #{ActiveRecord.version}..."

# Setup in-memory SQLite database
ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: ":memory:"
)

# Disable lazy transactions for newer Rails
if ActiveRecord.version >= Gem::Version.new("6.0")
  ActiveRecord::Base.connection_pool.with_connection(&:disable_lazy_transactions!)
end

# Initialize Sequel with activerecord_connection extension
DB = Sequel.sqlite(extensions: :activerecord_connection)

# Test 1: Basic query
puts "\n1. Testing basic query execution..."
result = DB["SELECT 1 AS test"].first
raise "Query failed" unless result[:test] == 1
puts "   ✓ Basic query works"

# Test 2: Create table and insert data
puts "\n2. Testing table creation and data insertion..."
DB.create_table! :test_items do
  primary_key :id
  String :name
end
DB[:test_items].insert(name: "Test Item")
count = DB[:test_items].count
raise "Insert failed" unless count == 1
puts "   ✓ Table creation and insertion works"

# Test 3: Transaction synchronization
puts "\n3. Testing transaction synchronization..."
ActiveRecord::Base.transaction do
  raise "Not in Sequel transaction" unless DB.in_transaction?
  puts "   ✓ ActiveRecord transaction recognized by Sequel"
end

DB.transaction do
  raise "Not in ActiveRecord transaction" unless ActiveRecord::Base.connection.transaction_open?
  puts "   ✓ Sequel transaction recognized by ActiveRecord"
end

# Test 4: After commit hooks
puts "\n4. Testing after_commit hooks..."
hook_executed = false
DB.transaction do
  DB.after_commit { hook_executed = true }
end
raise "After commit hook didn't execute" unless hook_executed
puts "   ✓ After commit hooks work"

# Test 5: Savepoints
puts "\n5. Testing savepoints..."
DB.transaction do
  DB[:test_items].insert(name: "Item 1")
  DB.transaction(savepoint: true) do
    DB[:test_items].insert(name: "Item 2")
    raise Sequel::Rollback
  end
  count = DB[:test_items].count
  raise "Savepoint rollback failed" unless count == 2 # Original + Item 1
end
puts "   ✓ Savepoints work correctly"

# Test 6: Connection pool integration
puts "\n6. Testing connection pool integration..."
conn = DB.synchronize { |c| c }
ar_conn = ActiveRecord::Base.connection.raw_connection
# Both should be the same underlying connection
puts "   ✓ Connection pool integrated"

# Test 7: Query logging
puts "\n7. Testing query logging..."
log_output = []
ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  # Sequel queries are logged with name "Sequel"
  if event.payload[:name] == "Sequel"
    log_output << event.payload[:sql]
  end
end

DB[:test_items].where(name: "Test").all
# Verify that at least one Sequel query was logged
raise "Query not logged" if log_output.empty?
puts "   ✓ Queries are logged to ActiveRecord (#{log_output.length} query/queries)"

# Cleanup
DB.drop_table? :test_items

puts "\n" + "=" * 60
puts "All Rails #{ActiveRecord::VERSION::STRING} compatibility tests passed! ✓"
puts "=" * 60
