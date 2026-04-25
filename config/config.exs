import Config

config :soot_contracts,
  ash_domains: [SootContracts.Domain]

if File.exists?(Path.join([__DIR__, "#{config_env()}.exs"])) do
  import_config "#{config_env()}.exs"
end
