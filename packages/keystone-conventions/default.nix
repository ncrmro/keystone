{
  runCommand,
  keystone-src,
}:
runCommand "keystone-conventions" { } ''
  mkdir -p $out
  cp -r ${keystone-src}/conventions/* $out/
''
