# frozen_string_literal: true

version = File.read(File.join(__dir__, 'VERSION')).strip.freeze

Gem::Specification.new('darkroom', version) do |spec|
  spec.authors       = ['Nate Pickens']
  spec.summary       = 'A fast, lightweight, and straightforward web asset management library.'
  spec.description   = 'Darkroom provides web asset compilation, bundling, and minification without any '\
                       'external tools, manifest files, or special comment syntax. CSS and JavaScript '\
                       'bundles are automatically generated based on import statements native to each '\
                       'language. Darkroom is also extensible, allowing support to be added for arbitrary '\
                       'file types.'
  spec.homepage      = 'https://github.com/npickens/darkroom'
  spec.license       = 'MIT'
  spec.files         = Dir['lib/**/*.rb', 'LICENSE', 'README.md', 'VERSION']

  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = 'https://rubygems.org'
    spec.metadata['homepage_uri'] = spec.homepage
    spec.metadata['source_code_uri'] = spec.homepage
  else
    raise('RubyGems 2.0 or newer is required to protect against public gem pushes.')
  end

  spec.required_ruby_version = '>= 2.5.8'

  spec.add_runtime_dependency('base64', '~> 0.2')
  spec.add_development_dependency('bundler', '~> 2.0')
  spec.add_development_dependency('minitest', '>= 5.11.2', '< 6.0.0')
end
