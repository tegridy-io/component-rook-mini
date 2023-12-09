local com = import 'lib/commodore.libjsonnet';

local template_files = [
  'securityContextConstraints',
];

local templates = [
  {
    name: template_file,
    content: com.yaml_load_all(std.extVar('output_path') + '/' + template_file + '.yaml'),
  }
  for template_file in template_files
];

{
  [template.name]: std.filter(function(it) it != null, template.content)
  for template in templates
}
