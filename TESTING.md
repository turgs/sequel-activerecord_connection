# Testing and Future Compatibility

This document provides guidance on testing the gem for compatibility with Rails updates and other gems.

## Testing with Rails Runner Scripts

To validate that the gem works correctly with your Rails application, you can run these basic integration tests using `rails runner`:

### Basic Connection Test

```ruby
# test/scripts/basic_connection_test.rb
# Run with: rails runner test/scripts/basic_connection_test.rb

require "sequel"

# Initialize Sequel with activerecord_connection extension
DB = Sequel.postgres(extensions: :activerecord_connection) # or mysql2, sqlite, etc.

puts "Testing Sequel with ActiveRecord connection..."

# Test 1: Basic query execution
result = DB["SELECT 1 AS test"].first
raise "Query failed" unless result[:test] == 1
puts "✓ Basic query execution works"

# Test 2: Transaction state synchronization
ActiveRecord::Base.transaction do
  raise "Not in transaction" unless DB.in_transaction?
  puts "✓ Transaction state synchronized with ActiveRecord"
end

# Test 3: After commit hooks
committed = false
DB.transaction do
  DB.after_commit { committed = true }
end
raise "After commit hook didn't execute" unless committed
puts "✓ After commit hooks work"

puts "\nAll basic tests passed!"
```

### Multi-Database Test (for apps using multiple databases)

```ruby
# test/scripts/multi_database_test.rb
# Run with: rails runner test/scripts/multi_database_test.rb

require "sequel"

# Test with different ActiveRecord models
class PrimaryModel < ActiveRecord::Base
  self.abstract_class = true
  connects_to database: { writing: :primary }
end

class SecondaryModel < ActiveRecord::Base
  self.abstract_class = true
  connects_to database: { writing: :secondary }
end

# Initialize Sequel for each connection
DB_PRIMARY = Sequel.postgres(extensions: :activerecord_connection)
DB_PRIMARY.activerecord_model = PrimaryModel

DB_SECONDARY = Sequel.postgres(extensions: :activerecord_connection)
DB_SECONDARY.activerecord_model = SecondaryModel

puts "Testing Sequel with multiple ActiveRecord connections..."

# Test that each DB uses the correct connection
puts "✓ Multiple database connections configured"

puts "\nMulti-database tests passed!"
```

### Transaction Isolation Test

```ruby
# test/scripts/transaction_isolation_test.rb
# Run with: rails runner test/scripts/transaction_isolation_test.rb

require "sequel"

DB = Sequel.postgres(extensions: :activerecord_connection)

puts "Testing transaction isolation levels..."

# Test different isolation levels
[:uncommitted, :committed, :repeatable, :serializable].each do |level|
  begin
    DB.transaction(isolation: level) do
      puts "✓ Transaction with #{level} isolation level works"
    end
  rescue => e
    puts "⚠ Transaction with #{level} isolation level not supported: #{e.message}"
  end
end

puts "\nTransaction isolation tests completed!"
```

## Compatibility with activerecord-tenanted

The `activerecord-tenanted` gem (https://github.com/basecamp/activerecord-tenanted) requires Rails 8.1+ and creates separate database connections for each tenant using horizontal sharding.

### Potential Compatibility Considerations

1. **Connection Pool Management**: Both gems work at the connection pool level. `activerecord-tenanted` swaps connection pools per tenant, while `sequel-activerecord_connection` reuses the active connection.

2. **Model Configuration**: When using `activerecord-tenanted`, you can configure Sequel to use a specific tenant's model:

```ruby
# In tenant context
DB = Sequel.postgres(extensions: :activerecord_connection)
DB.activerecord_model = TenantModel # Use the tenanted model
```

3. **Transaction Handling**: Both gems should work together as long as transactions are managed through the same connection. Always ensure transactions are initiated through the same model/connection that Sequel is configured to use.

### Testing with activerecord-tenanted

```ruby
# test/scripts/tenanted_test.rb
# Run with: rails runner test/scripts/tenanted_test.rb
# Requires: activerecord-tenanted gem

require "sequel"

# Assuming TenantedRecord is your tenanted model
DB = Sequel.postgres(extensions: :activerecord_connection)
DB.activerecord_model = TenantedRecord

# Test within tenant context
TenantedRecord.with_tenant(Tenant.first) do
  # All Sequel queries should use the tenant's database
  result = DB["SELECT 1 AS test"].first
  puts "✓ Sequel works within tenant context"
  
  # Test transactions
  DB.transaction do
    puts "✓ Transactions work within tenant context"
  end
end

puts "\nTenanted tests passed!"
```

## Future-Proofing Strategy

To ensure compatibility with future Rails versions:

1. **Monitor ActiveRecord Changes**: Subscribe to Rails changelog and watch for changes in:
   - Connection handling and pooling
   - Transaction management and hooks
   - Database adapter changes

2. **Test Against Edge Rails**: Periodically test against `rails/main` to catch breaking changes early:
   ```ruby
   # In Gemfile.local or test environment
   gem "rails", github: "rails/rails"
   ```

3. **Version Constraints**: The gem uses `< 8.2` constraint to allow patch releases but prevent untested major version bumps. Update this constraint when testing confirms compatibility with new versions.

4. **CI Coverage**: The gem's CI tests against multiple Ruby and Rails versions. When a new Rails version is released:
   - Add a new Gemfile in `gemfiles/`
   - Update the CI matrix in `.github/workflows/ci.yml`
   - Test all supported database adapters

5. **Adapter-Specific Testing**: While SQLite works out of the box, production apps should test with their specific database:
   - PostgreSQL
   - MySQL
   - SQL Server (if using)

## Common Issues and Solutions

### Connection Not Found
If you see "connection to server failed", ensure your ActiveRecord connection is established before initializing Sequel:
```ruby
ActiveRecord::Base.connection # Establish connection
DB = Sequel.postgres(extensions: :activerecord_connection)
```

### Transaction State Mismatch
If transaction state isn't synchronized, ensure you're using the same connection:
```ruby
# Don't mix different connection configurations
DB.activerecord_model = YourModel
```

### Performance Monitoring
Monitor for connection pool exhaustion when using both AR and Sequel heavily:
```ruby
# Check connection pool stats
ActiveRecord::Base.connection_pool.stat
```
