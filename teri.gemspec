lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'teri/version'

Gem::Specification.new do |spec|
  spec.name          = 'teri'
  spec.version       = Teri::VERSION
  spec.authors       = ['Jonathan Siegel']
  spec.email         = ['usiegj00@github.com']

  spec.summary       = 'Terminal interface for ledger-cli'
  spec.description   = 'A terminal interface for ledger-cli that makes it easier to code ' \
                       'transactions and reconcile accounts'
  spec.homepage      = 'https://github.com/usiegj00/teri'
  spec.license       = 'MIT'

  spec.required_ruby_version = '>= 3.3.0'

  spec.files         = Dir.glob('{bin,lib}/**/*') + ['LICENSE.txt', 'README.md']
  spec.bindir        = 'bin'
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']
  spec.metadata      = {
    'homepage_uri' => spec.homepage,
    'rubygems_mfa_required' => 'true',
    'source_code_uri' => spec.homepage,
  }

  # Runtime dependencies
  spec.add_dependency 'ruby-openai', '~> 6.3'
  spec.add_dependency 'thor', '~> 1.2'
  spec.add_dependency 'tty-prompt', '~> 0.23'
end
