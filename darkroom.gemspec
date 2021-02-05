# frozen_string_literal: true

version = File.read(File.expand_path('../VERSION', __FILE__)).strip

Gem::Specification.new('darkroom', version) do |spec|
  spec.authors       = ['Nate Pickens']
  spec.summary       = 'A fast, lightweight, and straightforward web asset management library.'
  spec.description   = 'Darkroom provides simple web asset management complete with dependency bundling '\
                       'based on import statements, compilation, and minification.'
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

  spec.required_ruby_version = '>= 2.3'

  spec.add_development_dependency('bundler', '~> 2.0')
  spec.add_development_dependency('minitest', '~> 5.11')
end
