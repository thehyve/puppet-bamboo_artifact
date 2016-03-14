bamboo\_artifact
================

Simply native type that downloads an artifact from bamboo. It queries the Bamboo
API to make sure that the build was successful.

The build number defaults to `latest`. In that case, on each run, puppet will
try to determine if there is a new successful build available, and update the
local file if there is.

Sample:

```
bamboo_artifact { '/opt/transmart.war':
    ensure        => present,
    server        => 'https://ci.ctmmtrait.nl',
    plan          => 'TM-HEIMDEV',
    artifact_path => 'shared/-transmartApp-WAR/transmart.war',
    user          => 'transmart',
    build         => 'latest',
}
```
