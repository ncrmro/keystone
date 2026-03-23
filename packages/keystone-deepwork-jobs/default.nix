{
  lib,
  runCommand,
  keystone-src,
}:
runCommand "keystone-deepwork-jobs"
  {
    meta = with lib; {
      description = "Keystone repository DeepWork workflow jobs";
      license = licenses.mit;
    };
  }
  ''
    mkdir -p $out
    if [ -d ${keystone-src}/.deepwork/jobs ] && [ "$(ls -A ${keystone-src}/.deepwork/jobs 2>/dev/null)" ]; then
      for d in ${keystone-src}/.deepwork/jobs/*/; do
        [ -d "$d" ] && cp -r "$d" $out/
      done
    fi
  ''
