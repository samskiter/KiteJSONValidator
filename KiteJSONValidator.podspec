Pod::Spec.new do |s|
  s.name         = "KiteJSONValidator"
  s.version      = "0.1"
  s.summary      = "A native Objective-C JSON schema validator supporting JSON Schema draft 4"
  s.description  = <<-DESC
					A native Objective-C JSON schema validator supporting [JSON Schema draft 4] [schemalink] released under the MIT license.

					Notes: This implementation does not support inline dereferencing (see [section 7.2.3] [section723] of the JSON Schema Spec).

					Development discussion [here] [devLink]

					[schemalink]: http://tools.ietf.org/html/draft-zyp-json-schema-04
					[section723]: http://json-schema.org/latest/json-schema-core.html#anchor30
					[devlink]: https://groups.google.com/forum/#!forum/kitejsonvalidator-development
                   DESC
  s.homepage     = "https://github.com/samskiter/KiteJSONValidator"
  s.license      = "MIT"
  s.author       = { "Sam Duke" => "email.not.published@mailinator.com" }
  s.platform     = :ios
  s.ios.deployment_target = "7.0"

  s.source       = { :git => "https://github.com/samskiter/KiteJSONValidator.git", :tag => '0.1' }
  s.source_files  = "KiteJSONValidator/*.{h,m}"

  s.requires_arc = true
end
