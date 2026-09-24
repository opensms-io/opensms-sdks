# frozen_string_literal: true

require_relative "lib/opensms/version"

Gem::Specification.new do |spec|
  spec.name = "opensms"
  spec.version = Opensms::VERSION
  spec.authors = ["OpenSMS"]
  spec.email = ["engineering@opensms.io"]

  spec.summary = "Ruby SDK for the OpenSMS API."
  spec.description = "Send SMS and OTPs, run batches, look up numbers, and manage contacts, templates, " \
                     "webhooks, numbers, sender IDs, suppressions and wallet through the OpenSMS API. " \
                     "Zero runtime dependencies."
  spec.homepage = "https://opensms.io"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "https://github.com/opensms-io/opensms-sdks",
    "documentation_uri" => "https://docs.opensms.io",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb"] + ["README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  # Zero runtime dependencies: the SDK uses only the Ruby standard library
  # (net/http, json, openssl, securerandom, time, uri).

  spec.add_development_dependency "minitest", ">= 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
