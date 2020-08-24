#!/bin/bash

set -e

SAMBA_DOMAIN=${SAMBA_DOMAIN:-SAMDOM}
SAMBA_REALM=${SAMBA_REALM:-SAMDOM.EXAMPLE.COM}
LDAP_ALLOW_INSECURE=${LDAP_ALLOW_INSECURE:-false}

if [[ $SAMBA_HOST_IP ]]; then
  SAMBA_HOST_IP="--host-ip=${SAMBA_HOST_IP}"
fi

SAMBA_CONF_BACKUP=/smb.conf
KRBKEYTAP_CONF_BACKUP=/krb5.keytab

appSetup() {
  echo "Initializing samba database..."

  # Generate passwords or re-use them from the environment
  ROOT_PASSWORD=${ROOT_PASSWORD:-Member22%}
  SAMBA_ADMIN_PASSWORD=${SAMBA_ADMIN_PASSWORD:-Member22%}
  export KERBEROS_PASSWORD=${KERBEROS_PASSWORD:-$(pwgen -cny 10 1)}
  echo "root:$ROOT_PASSWORD" | chpasswd
  echo Root password: $ROOT_PASSWORD
  echo Samba administrator password: $SAMBA_ADMIN_PASSWORD
  echo Kerberos KDC database master key: $KERBEROS_PASSWORD

  # Provision Samba
  rm -f /etc/samba/smb.conf
  rm -rf /var/lib/samba/private/
  samba-tool domain provision --use-rfc2307 --domain=$SAMBA_DOMAIN --realm=$SAMBA_REALM --server-role=dc \
    --dns-backend=BIND9_DLZ --adminpass=$SAMBA_ADMIN_PASSWORD $SAMBA_HOST_IP
  cp /var/lib/samba/private/krb5.conf /etc/krb5.conf
  if [ "${LDAP_ALLOW_INSECURE,,}" == "true" ]; then
    sed -i "/\[global\]/a \
	    \\\t\# enable unencrypted passwords\n\
    	ldap server require strong auth = no\
    	" /etc/samba/smb.conf
    samba-tool domain passwordsettings set --complexity=off
    samba-tool domain passwordsettings set --history-length=0
    samba-tool domain passwordsettings set --min-pwd-length=0
    samba-tool domain passwordsettings set --min-pwd-age=0
    samba-tool domain passwordsettings set --max-pwd-age=0
  fi
  # Create Kerberos database
  expect kdb5_util_create.expect

  # Export kerberos keytab for use with sssd
  if [ "${OMIT_EXPORT_KEY_TAB}" != "true" ]; then
    samba-tool domain exportkeytab /etc/krb5.keytab --principal ${HOSTNAME}\$
    cp /etc/krb5.keytab $KRBKEYTAP_CONF_BACKUP
  fi

  # Import users from SAMBA_USERS
  if [ -n "${SAMBA_USERS}" ]; then
    IFS="," read -a users <<< ${SAMBA_USERS}
    for userpassword in "${users[@]}"; do
      samba-tool user create ${userpassword/:/ }
    done
  fi

  cp /etc/samba/smb.conf $SAMBA_CONF_BACKUP
}

appStart() {
  if [ -f $SAMBA_CONF_BACKUP ]; then
    echo "Skipping setup and restoring configurations..."
    cp $SAMBA_CONF_BACKUP /etc/samba/smb.conf
    # cp -r /samba_bkp/* /var/lib/samba/
    [ -f $KRBKEYTAP_CONF_BACKUP ] && cp $KRBKEYTAP_CONF_BACKUP /etc/krb5.keytab
  else
    appSetup
  fi

  # Start the services
  /usr/bin/supervisord
}

appHelp() {
  echo "Available options:"
  echo " app:start          - Starts all services needed for Samba AD DC"
  echo " app:setup          - First time setup."
  echo " app:setup_start    - First time setup and start."
  echo " app:help           - Displays the help"
  echo " [command]          - Execute the specified linux command eg. /bin/bash."
}

case "$1" in
  app:start)
    appStart
    ;;
  app:setup)
    appSetup
    ;;
  app:setup_start)
    appSetup
    appStart
    ;;
  app:help)
    appHelp
    ;;
  *)
    if [ -x $1 ]; then
      $1
    else
      prog=$(which $1)
      if [ -n "${prog}" ]; then
        shift 1
        $prog $@
      else
        appHelp
      fi
    fi
    ;;
esac

exit 0
