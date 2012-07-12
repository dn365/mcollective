# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = "mcollective"
  s.version = "2.1.0"
  s.authors = "dn365"
  s.description = "Server libraries for the mcollective Application Server"
  s.email = "dn365@163.com"
  s.files = Dir.glob('{bin,lib,doc}/**/*') + %w[mcollective.init COPYING]
  s.executables = ["mcollectived"]
  s.require_paths = ['lib']
  s.summary = "Server libraries for The Marionette Collective"

  s.add_dependency 'systemu'
	s.add_dependency 'json'
	s.add_dependency 'stomp'


end