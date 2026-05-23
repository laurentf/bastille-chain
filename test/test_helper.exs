# Test Helper for Bastille Blockchain
# Configures test environment and loads test utilities

# Exclude integration tests by default — they stop and restart the global
# storage GenServers (Blocks, Chain, State, Index, …) which destabilizes the
# rest of the suite when run alongside unit tests. Run them on demand with:
#   mix test --include integration
# or in a dedicated CI step.
ExUnit.start(exclude: [:integration])

# Configure test logger
Logger.configure(level: :warning)

# Load test support modules
Code.require_file("support/test_helper.ex", __DIR__)

# Clean up before running tests
if Application.get_env(:bastille, :storage_base_path) do
  test_data_path = Application.get_env(:bastille, :storage_base_path)
  if File.exists?(test_data_path), do: File.rm_rf!(test_data_path)
end

# Clean up default data directory
if File.exists?("data"), do: File.rm_rf!("data")
