#!/bin/bash

TEST_MODE=false                                 # Test mode to use script from command line, being prompted for username and password
LDAP_SERVER='10.x.x.x'                          # Active Directory Server.
BASE_DN='dc=example,dc=com'    					# Base Domain Name
GROUP_ON_LDAP='ou=GROUPS,ou=GROUP_ON_LDAP'      # Where is the group on LDAP
DOMAIN_NAME='EXAMPLE'                           # Domain Name EXAMPLE
MEMBER_ATTR='member'                            # Attribute of Group VPN
VPN_GROUP='ESP-ACCESS-VPN'		            	# Group of users witn access to VPN.
CRED_FILE="$1"                                  # Temporary file with credentials (username, password) is passed to script as first argument
MAX_LEN=256                                     # Maximum length in characters of username and password; longer strings will not be accepted

uid=''                       					# User Id variable 
pw=''                        					# Password variable


if $TEST_MODE
  then
  echo "Running in test mode"
  #read -p "Username: " uid
  #read -s -p "Password: " pw
  echo
elif ! [ -r "$CRED_FILE" ]
  then
  echo "ERROR: Credentials file '${CRED_FILE}' does not exist or is not readable"
  exit 1
elif [ $(wc -l <"$CRED_FILE") -ne 2 ]
  then
  echo "ERROR: Credentials file '${CRED_FILE}' does not exactly have two lines of text"
  exit 2
else
  echo "Reading username and password from credentials file '${CRED_FILE}'"
  uid=$(head -n 1 "$CRED_FILE")
  pw=$(tail -n 1 "$CRED_FILE")
fi

if [ $(echo "$uid" | wc -m) -gt $MAX_LEN ]
  then
  echo "ERROR: Username is longer than $MAX_LEN characters - this is forbidden"
  exit 3
fi

if [ $(echo "$pw" | wc -m) -gt $MAX_LEN ]
  then
  echo "ERROR: Password is longer than $MAX_LEN characters - this is forbidden"
  exit 4
fi
# username and common_name must be the same to allow access.
# users are not allowed to share their cert
usuariolowercase=`echo $uid | tr '[A-Z]' '[a-z]'`

if [ $usuariolowercase != $common_name ]; then
   echo "ACCESS DENIED - CERTIFICATE ISSUE username=$usuariolowercase cert=$common_name"
   echo "$(date +%Y%m%d-%H%M%S) DENIED  username=$usuariolowercase cert=$common_name" >> /var/log/openvpn/openvpn-access-tme.log
   exit 1
fi
echo "ACCESS GRANTED - CERTIFICATE OK - username=$usuariolowercase cert=$common_name"
echo "$(date +%Y%m%d-%H%M%S) GRANTED username=$usuariolowercase cert=$common_name" >> /var/log/openvpn/openvpn-access-tme.log

#
# Check if the user have accents on namo or second names, compare entire string encode on base64.
# The active directory return on base64 if containts accents.
# 2020-08-24 RAUL PEREZ - QUERY OF USER WITH LDAPS PORT 636
#QUERY_USER=`ldapsearch -LLL -x -h ${LDAP_SERVER} -D ${uid}@${DOMAIN_NAME} -w "${pw}" -b ${BASE_DN} "sAMaccountName=$uid" dn | perl -p00e 's/\r?\n //g' | head -n 1`
QUERY_USER=`ldapsearch -LLL -x -H ldaps://${LDAP_SERVER} -D ${uid}@${DOMAIN_NAME} -w "${pw}" -b ${BASE_DN} "sAMaccountName=$uid" dn | perl -p00e 's/\r?\n //g' | head -n 1`
echo "QUERY_USER: $QUERY_USER"
DN_NOENCODE64_USER=`echo $QUERY_USER | grep "dn: " | cut -c5-`
echo "USUARIO_SIN ACENTOS: $DN_NOENCODE64_USER"
DN_ENCODE64_USER=`echo $QUERY_USER | grep "dn:: " | cut -c6- | awk '{ print $1 }'`
echo "USUARIO_CON ACENTOS: $DN_ENCODE64_USER"
if [ -n "${DN_ENCODE64_USER}" ]
  then
    #DN_USER=`echo $DN_ENCODE64_USER | base64 -d`
    DN_USER=$DN_ENCODE64_USER
else
  DN_USER=$DN_NOENCODE64_USER
fi


# Search if DN of user is a VPN group member(attribute), and compare on base64 if the user containts accents.
# 2020-08-24 RAUL PEREZ -  QUERY OF USER WITH LDAPS PORT 636
#QUERY_USER_GROUP=`ldapsearch -LLL -x -h ${LDAP_SERVER} -D ${uid}@${DOMAIN_NAME} -w "${pw}" -b "cn=${VPN_GROUP},${GROUP_ON_LDAP},${BASE_DN}" | perl -p00e 's/\r?\n //g'`
QUERY_USER_GROUP=`ldapsearch -LLL -x -H ldaps://${LDAP_SERVER} -D ${uid}@${DOMAIN_NAME} -w "${pw}" -b "cn=${VPN_GROUP},${GROUP_ON_LDAP},${BASE_DN}" | perl -p00e 's/\r?\n //g'`

DN_USER_ON_GROUP_NOENCODE=`echo $QUERY_USER_GROUP | grep "member: " | cut -c9- | grep "$DN_USER"`
DN_USER_ON_GROUP_ENCODE64=`echo $QUERY_USER_GROUP | grep "member:: " | cut -c10- | grep "$DN_USER"`

if [ -n "${DN_USER_ON_GROUP_ENCODE64}" ]
  then
    #DN_USER=`echo $DN_ENCODE64_USER | base64 -d`
    DN_USER_ON_GROUP=$DN_USER_ON_GROUP_ENCODE64
else
  DN_USER_ON_GROUP=$DN_USER_ON_GROUP_NOENCODE
fi

# Check if DN_USER is on VPN_GROUP
#
if [ -n "${DN_USER_ON_GROUP}" ]
  then
    #echo "CONTENIDO DEL USUARI:"$DN_USER
    #echo "CONTENIDO DEL GRUPO: "$DN_USER_ON_GROUP
    RESULT='TRUE'
    #echo $RESULT
else
    RESULT='FALSE'
fi

echo "LDAP compare result: $RESULT"

if [ "$RESULT" = 'TRUE' ]
  then
  echo "User '${uid}' is a member of group '${VPN_GROUP}'"
  exit 0
else
  echo "ERROR: LDAP connection error or user '${uid}' not in group '${VPN_GROUP}'"
  exit 5
fi
