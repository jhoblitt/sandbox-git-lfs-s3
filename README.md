sandbox-git-lfs-s3
===

A vagrantized/puppetized deployment of git-lfs-s3

manage secrets
---

AWS API tokens, TLS certificates, etc. secrets are stored in
`./hieradata/common.eyaml` which needs to be converted to `.yaml` before
puppet will be able to locate it.

Existing encrypted values will need to be edited unless you have the `./keys/` directory used to encrypt

    bundle install

    bundle exec rake createkeys
    bundle exec rake edit

    bundle exec rake decrypt

running Vagrant
---

VirtualBox and AWS/EC2 are supported.  These environment variables need to be
declared in order to use the `aws` provider.  The hardcoded ami is not public
and also will need to be edited.

    export AWS_ACCESS_KEY_ID="..."
    export AWS_SECRET_ACCESS_KEY="..."
    export AWS_DEFAULT_REGION="..."
    vagrant up --provider=aws
