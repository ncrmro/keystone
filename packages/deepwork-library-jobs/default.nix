{
  runCommand,
  deepwork-src,
}:
runCommand "deepwork-library-jobs" { } ''
  mkdir -p $out
  cp -r ${deepwork-src}/library/jobs/spec_driven_development $out/
''
