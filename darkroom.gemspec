# frozen_string_literal: true

version = File.read(File.join(__dir__, 'VERSION')).strip.freeze

Gem::Specification.new('darkroom', version) do |spec|
  spec.authors       = ['Nate Pickens']
  spec.summary       = 'A simple and straightforward web asset management library.'
  spec.description   = 'Darkroom provides web asset compilation, bundling, and minification without any ' \
                       'external tools, manifest files, or special comment syntax. CSS and JavaScript ' \
                       'bundles are automatically generated based on import statements native to each ' \
                       'language. Darkroom is also extensible, allowing support to be added for ' \
                       'arbitrary file types.'
  spec.homepage      = 'https://github.com/npickens/darkroom'
  spec.license       = 'MIT'
  spec.files         = Dir['lib/**/*.rb', 'CHANGELOG.md', 'LICENSE', 'README.md', 'VERSION']

  spec.metadata      = {
    'bug_tracker_uri' => 'https://github.com/npickens/darkroom/issues',
    'changelog_uri' => 'https://github.com/npickens/darkroom/blob/master/CHANGELOG.md',
    'documentation_uri' => "https://github.com/npickens/darkroom/blob/#{version}/README.md",
    'source_code_uri' => "https://github.com/npickens/darkroom/tree/#{version}",
  }

  spec.required_ruby_version = '>= 3.0.0'
  spec.required_rubygems_version = '>= 2.0.0'

  spec.add_dependency('base64', '~> 0.2')
  spec.add_development_dependency('bundler', '~> 2.0')
  spec.add_development_dependency('minitest', '~> 5.24')
  spec.add_development_dependency('minitest-reporters', '~> 1.7')
end
