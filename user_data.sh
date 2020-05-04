#!/usr/bin/env bash

yum update -y
yum install -y epel-release
yum install -y python-pip jq

pip install --upgrade awscli

### AUTO FETCH SSH KEYS FROM BUCKET ###

cat <<"EOF" > /home/ec2-user/update_ssh_authorized_keys.sh
#!/usr/bin/env bash
set -e
BUCKET_NAME=formunauts-production-bastion-keys
BUCKET_URI=
SSH_USER=ec2-user
MARKER="# KEYS_BELOW_WILL_BE_UPDATED_BY_TERRAFORM"
KEYS_FILE=/home/$SSH_USER/.ssh/authorized_keys
TEMP_KEYS_FILE=$(mktemp /tmp/authorized_keys.XXXXXX)
PUB_KEYS_DIR=/home/$SSH_USER/pub_key_files/
PATH=/usr/local/bin:$PATH
[[ -z $BUCKET_URI ]] && BUCKET_URI="s3://$BUCKET_NAME/"
mkdir -p $PUB_KEYS_DIR
# Add marker, if not present, and copy static content.
grep -Fxq "$MARKER" $KEYS_FILE || echo -e "\n$MARKER" >> $KEYS_FILE
line=$(grep -n "$MARKER" $KEYS_FILE | cut -d ":" -f 1)
head -n $line $KEYS_FILE > $TEMP_KEYS_FILE
# Synchronize the keys from the bucket.
aws s3 sync --delete --exact-timestamps $BUCKET_URI $PUB_KEYS_DIR
for filename in $PUB_KEYS_DIR/*; do
    [ -f "$filename" ] || continue
    sed 's/\n\?$/\n/' < $filename >> $TEMP_KEYS_FILE
done
# Move the new authorized keys in place.
chown $SSH_USER:$SSH_USER $KEYS_FILE
chmod 600 $KEYS_FILE
mv $TEMP_KEYS_FILE $KEYS_FILE
if [[ $(command -v "selinuxenabled") ]]; then
    restorecon -R -v $KEYS_FILE
fi
EOF

cat <<"EOF" > /home/ec2-user/.ssh/config
Host *
    StrictHostKeyChecking no
EOF
chmod 600 /home/ec2-user/.ssh/config
chown ec2-user:ec2-user /home/ec2-user/.ssh/config

chown ec2-user:ec2-user /home/ec2-user/update_ssh_authorized_keys.sh
chmod 755 /home/ec2-user/update_ssh_authorized_keys.sh

# Execute now
su ec2-user -c /home/ec2-user/update_ssh_authorized_keys.sh

# Be backwards compatible with old cron update enabler
if [ "1" = 'true' -a -z "0 * * * *" ]; then
  keys_update_frequency="0 * * * *"
else
  keys_update_frequency="0 * * * *"
fi

# Add to cron
if [ -n "$keys_update_frequency" ]; then
  croncmd="/home/ec2-user/update_ssh_authorized_keys.sh"
  cronjob="$keys_update_frequency $croncmd"
  ( crontab -u ec2-user -l | grep -v "$croncmd" ; echo "$cronjob" ) | crontab -u ec2-user -
fi

# Append addition user-data script


