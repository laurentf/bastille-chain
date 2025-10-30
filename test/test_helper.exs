# Test Helper for Bastille Blockchain
# Configures test environment and loads test utilities

ExUnit.start()

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
