require_relative "lib/tr_module/version"

Gem::Specification.new do |spec|
  spec.name        = "tr_module"
  spec.version     = TrModule::VERSION
  spec.authors     = [ "jtromp" ]
  spec.email       = [ "jtromp@datacollectors.net" ]
  spec.homepage    = "https://github.com/datacollectors-net/tr_module"
  spec.summary     = "Rails engine for iframe-embedded module communication with a host application."
  spec.description = "TrModule provides host-context authentication, session management, " \
                     "CSRF-safe iframe embedding, and a Stimulus controller for postMessage-based " \
                     "communication between a Rails module and its host application."
  spec.license     = "MIT"

  spec.required_ruby_version = ">= 3.2"

  spec.metadata["allowed_push_host"] = "https://rubygems.pkg.github.com/datacollectors-net"
  spec.metadata["homepage_uri"]      = spec.homepage
  spec.metadata["source_code_uri"]   = "https://github.com/datacollectors-net/tr_module"
  spec.metadata["changelog_uri"]     = "https://github.com/datacollectors-net/tr_module/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md", "CHANGELOG.md"]
  end

  spec.add_dependency "rails", ">= 8.1.3"
  spec.add_dependency "importmap-rails"
end
