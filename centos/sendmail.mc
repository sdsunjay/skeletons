divert(-1)dnl
dnl #
dnl # This is the sendmail macro config file for m4. If you make changes to
dnl # /etc/mail/sendmail.mc, you will need to regenerate the
dnl # /etc/mail/sendmail.cf file by confirming that the sendmail-cf package is
dnl # installed and then performing a
dnl #
dnl #     make -C /etc/mail
dnl #
include(`/usr/share/sendmail-cf/m4/cf.m4')dnl
VERSIONID(`setup for linux')dnl
OSTYPE(`linux')dnl
dnl #
dnl # Do not advertize sendmail version.
dnl #
define(`confSMTP_LOGIN_MSG', `$j Sendmail; $b')dnl
dnl #
dnl # default logging level is 9, you might want to set it higher to
dnl # debug the configuration
dnl #
define(`confLOG_LEVEL', `9')dnl
dnl #
dnl # Uncomment and edit the following line if your outgoing mail needs to
dnl # be sent out through an external mail server:
dnl #
dnl define(`SMART_HOST', `smtp.your.provider')dnl
dnl # define(`SMART_HOST', `smtp.gmail.com')dnl
dnl # define(`RELAY_MAILER_ARGS', `TCP $h 587')dnl
dnl # define(`ESMTP_MAILER_ARGS', `TCP $h 587')dnl
dnl #
define(`confDEF_USER_ID', ``8:12'')dnl
dnl define(`confAUTO_REBUILD')dnl
dnl #The timeout waiting for an initial connect() to complete. Set to 1min.
dnl # This can only shorten connection timeouts; the kernel silently enforces an absolute maximum (which varies depending on the system).
define(`confTO_CONNECT', `1m')dnl
define(`confTO_ICONNECT', `15s')dnl
define(`confTO_HELO', `2m')dnl
define(`confTO_MAIL', `1m')dnl
define(`confTO_RCPT', `1m')dnl
define(`confTO_DATAINIT', `1m')dnl
define(`confTO_DATABLOCK', `1m')dnl
define(`confTO_DATAFINAL', `1m')dnl
define(`confTO_RSET', `1m')dnl
define(`confTO_QUIT', `1m')dnl
define(`confTO_MISC', `1m')dnl
define(`confTO_COMMAND', `1m')dnl
define(`confTO_STARTTLS', `2m')dnl

define(`confTRY_NULL_MX_LIST', `True')dnl
define(`confDONT_PROBE_INTERFACES', `True')dnl
define(`PROCMAIL_MAILER_PATH', `/usr/bin/procmail')dnl
define(`ALIAS_FILE', `/etc/aliases')dnl
define(`STATUS_FILE', `/var/log/mail/statistics')dnl
define(`UUCP_MAILER_MAX', `2000000')dnl
define(`confUSERDB_SPEC', `/etc/mail/userdb.db')dnl
define(`confPRIVACY_FLAGS', `authwarnings,novrfy,noexpn,restrictqrun')dnl
define(`confAUTH_OPTIONS', `A')dnl
dnl # 1 MB is the max size for an email message
define(`confMAX_MESSAGE_SIZE','1000000')dnl
define(`confMAXRCPTSPERMESSAGE', `50')dnl Denial of service Attacks
dnl #
dnl # The following allows relaying if the user authenticates, and disallows
dnl # plaintext authentication (PLAIN/LOGIN) on non-TLS links
dnl #
dnl define(`confAUTH_OPTIONS', `A p')dnl
dnl # 
dnl # PLAIN is the preferred plaintext authentication method and used by
dnl # Mozilla Mail and Evolution, though Outlook Express and other MUAs do
dnl # use LOGIN. Other mechanisms should be used if the connection is not
dnl # guaranteed secure.
dnl # Please remember that saslauthd needs to be running for AUTH. 
dnl #
dnl TRUST_AUTH_MECH(`EXTERNAL DIGEST-MD5 CRAM-MD5 LOGIN PLAIN')dnl
dnl define(`confAUTH_MECHANISMS', `EXTERNAL GSSAPI DIGEST-MD5 CRAM-MD5 LOGIN PLAIN')dnl
dnl define(`confAUTH_MECHANISMS', `EXTERNAL GSSAPI DIGEST-MD5 CRAM-MD5 LOGIN PLAIN')dnl
dnl #
dnl # Rudimentary information on creating certificates for sendmail TLS:
dnl #     cd /etc/pki/tls/certs; make sendmail.pem
dnl # Complete usage:
dnl #     make -C /etc/pki/tls/certs usage
dnl #

dnl # TO DO
define(`confCACERT_PATH', `/etc/pki/tls/certs')dnl
define(`confCACERT', `/etc/pki/tls/certs/ca-bundle.crt')dnl
define(`confSERVER_CERT', `/etc/pki/tls/certs/sendmail.pem')dnl
define(`confSERVER_KEY', `/etc/pki/tls/certs/sendmail.pem')dnl



dnl # ORIGINAL
dnl # define(`confCACERT_PATH', `/etc/pki/tls/certs')dnl
dnl # define(`confCACERT', `/etc/pki/tls/certs/ca-bundle.crt')dnl
dnl # define(`confSERVER_CERT', `/etc/pki/tls/certs/sendmail.pem')dnl
dnl # define(`confSERVER_KEY', `/etc/pki/tls/certs/sendmail.pem')dnl
dnl # define(`confCLIENT_CERT', `/etc/pki/tls/certs/sendmail.pem')dnl
dnl # define(`confCLIENT_KEY', `/etc/pki/tls/certs/sendmail.pem')dnl

dnl #
dnl # This allows sendmail to use a keyfile that is shared with OpenLDAP's
dnl # slapd, which requires the file to be readble by group ldap
dnl #
dnl define(`confDONT_BLAME_SENDMAIL', `groupreadablekeyfile')dnl
dnl #
dnl define(`confTO_QUEUEWARN', `4h')dnl
dnl define(`confTO_QUEUERETURN', `5d')dnl
define(`confQUEUE_LA', `3')dnl
define(`confREFUSE_LA', `5')dnl
define(`confTO_IDENT', `0')dnl
dnl FEATURE(delay_checks)dnl
FEATURE(`no_default_msa', `dnl')dnl
FEATURE(`smrsh', `/usr/sbin/smrsh')dnl
FEATURE(`mailertable', `hash -o /etc/mail/mailertable.db')dnl
FEATURE(`virtusertable', `hash -o /etc/mail/virtusertable.db')dnl With the help of virtual user table we can specify rules like mails sent to 'user1@domain1.com' should go to following address and mails sent to 'user1@domain2.com' should go to another address.
FEATURE(redirect)dnl
FEATURE(always_add_domain)dnl
FEATURE(use_cw_file)dnl make sendmail look for local-host-names file
FEATURE(use_ct_file)dnl
dnl #
dnl # The following limits the number of processes sendmail can fork to accept 
dnl # incoming messages or process its message queues to 20.) sendmail refuses 
dnl # to accept connections once it has reached its quota of child processes.
dnl #
define(`confMAX_DAEMON_CHILDREN', `3')dnl
dnl #
dnl # Limits the number of new connections per second. This caps the overhead 
dnl # incurred due to forking new sendmail processes. May be useful against 
dnl # DoS attacks or barrages of spam. (As mentioned below, a per-IP address 
dnl # limit would be useful but is not available as an option at this writing.)
dnl #
define(`confCONNECTION_RATE_THROTTLE', `3')dnl
dnl #
dnl # The -t option will retry delivery if e.g. the user runs over his quota.
dnl #


define(`confMAX_HOP', `35')dnl


FEATURE(local_procmail, `', `procmail -t -Y -a $h -d $u')dnl
FEATURE(`access_db', `hash -T<TMPF> -o /etc/mail/access.db')dnl
FEATURE(`blacklist_recipients')dnl
EXPOSED_USER(`root')dnl
dnl #
dnl # For using Cyrus-IMAPd as POP3/IMAP server through LMTP delivery uncomment
dnl # the following 2 definitions and activate below in the MAILER section the
dnl # cyrusv2 mailer.
dnl #
dnl define(`confLOCAL_MAILER', `cyrusv2')dnl
dnl define(`CYRUSV2_MAILER_ARGS', `FILE /var/lib/imap/socket/lmtp')dnl
dnl #
dnl # The following causes sendmail to only listen on the IPv4 loopback address
dnl # 127.0.0.1 and not on any other network devices. Remove the loopback
dnl # address restriction to accept email from the internet or intranet.

dnl # ORIGINAL 
dnl # DAEMON_OPTIONS(`Port=smtp,Addr=127.0.0.1, Name=MTA')dnl
dnl # Accept for the internet dnl
dnl # DAEMON_OPTIONS(`Port=smtp,Name=MTA')dnl
dnl #
dnl # The following causes sendmail to additionally listen to port 587 for
dnl # mail from MUAs that authenticate. Roaming users who can't reach their
dnl # preferred sendmail daemon due to port 25 being blocked or redirected find
dnl # this useful.
dnl #
dnl DAEMON_OPTIONS(`Port=submission, Name=MSA, M=Ea')dnl
dnl #
dnl # The following causes sendmail to additionally listen to port 465, but
dnl # starting immediately in TLS mode upon connecting. Port 25 or 587 followed
dnl # by STARTTLS is preferred, but roaming clients using Outlook Express can't
dnl # do STARTTLS on ports other than 25. Mozilla Mail can ONLY use STARTTLS
dnl # and doesn't support the deprecated smtps; Evolution <1.1.1 uses smtps
dnl # when SSL is enabled-- STARTTLS support is available in version 1.1.1.
dnl #
dnl # For this to work your OpenSSL certificates must be configured.
dnl #
dnl # TO DO
dnl # receive and send mail using smtps, port 465
DAEMON_OPTIONS(`Port=smtps, Name=TLSMTA, M=s')dnl
dnl #
dnl # The following causes sendmail to additionally listen on the IPv6 loopback
dnl # device. Remove the loopback address restriction listen to the network.
dnl #
dnl # DAEMON_OPTIONS(`port=smtp, Name=MTA-v6, Family=inet6')dnl
dnl #
dnl # enable both ipv6 and ipv4 in sendmail:
dnl #
DAEMON_OPTIONS(`Name=MTA-v4, Family=inet, Name=MTA-v6, Family=inet6')


dnl # We strongly recommend not accepting unresolvable domains if you want to
dnl # protect yourself from spam. However, the laptop and users on computers
dnl # that do not have 24x7 DNS do need this.
dnl #
dnl # FEATURE(`accept_unresolvable_domains')dnl
dnl #
dnl FEATURE(`relay_based_on_MX')dnl


dnl # ANTI SPAM FEATURE
dnl # For explanation http://www.acme.com/mail_filtering/sendmail_config.html
FEATURE(access_db)dnl
FEATURE(`greet_pause',5000)


define(`confDOMAIN_NAME', `sunjaydhama.com')dnl
FEATURE(`relay_entire_domain')dnl
define(`confDOMAIN_NAME', `sunjay.io')dnl
FEATURE(`relay_entire_domain')dnl
define(`confDOMAIN_NAME', `sunjay.me')dnl
FEATURE(`relay_entire_domain')dnl
define(`confDOMAIN_NAME', `sunjay.co')dnl
FEATURE(`relay_entire_domain')dnl
dnl # 
dnl # Also accept email sent to "localhost.localdomain" as local email.
dnl # 
dnl # LOCAL_DOMAIN(`localhost.localdomain')dnl
dnl #
dnl # The following example makes mail from this host and any additional
dnl # specified domains appear to be sent from mydomain.com
dnl #
MASQUERADE_AS(`sunjaydhama.com')dnl
dnl #
dnl # masquerade not just the headers, but the envelope as well
dnl #
FEATURE(masquerade_envelope)dnl
dnl #
dnl # masquerade not just @mydomainalias.com, but @*.mydomainalias.com as well
dnl #
FEATURE(masquerade_entire_domain)dnl
FEATURE(dnsbl, `sbl.spamhaus.org',`"Rejected due to Spamhaus listing see http://www.abuse.net/sbl.phtml?IP=" $&{clientaddr} " for more information"')dnl
FEATURE(dnsbl,`blackholes.mail-abuse.org',` Mail from $&{client_addr} rejected; see http://mail-abuse.org/cgi-bin/lookup?$& {client_addr}')dnl
FEATURE(dnsbl,`dialups.mail-abuse.org',` Mail from dial-up rejected; see http://mail-abuse.org/dul/enduser.htm')dnl
FEATURE(`dnsbl',`dnsbl.njabl.org',`"550 Mail from " $&{client_addr} " rejected - see http://njabl.org/"')dnl
dnl # FEATURE(`authinfo',`hash /etc/mail/authinfo')dnl
dnl # FEATURE(`nouucp',`reject')dnl

dnl # for SPAMASSASSIN
INPUT_MAIL_FILTER(`spamassassin', `S=unix:/var/run/spamass-milter/spamass-milter.sock, F=, T=C:15m;S:4m;R:4m;E:10m')dnl
define(`confMILTER_MACROS_CONNECT',`t, b, j, _, {daemon_name}, {if_name}, {if_addr}')dnl
define(`confMILTER_MACROS_HELO',`s, {tls_version}, {cipher}, {cipher_bits}, {cert_subject}, {cert_issuer}')dnl


dnl #
dnl MASQUERADE_DOMAIN(localhost)dnl
dnl MASQUERADE_DOMAIN(localhost.localdomain)dnl
dnl MASQUERADE_DOMAIN(mydomainalias.com)dnl
dnl MASQUERADE_DOMAIN(mydomain.lan)dnl
MAILER(smtp)dnl
MAILER(procmail)dnl
dnl MAILER(cyrusv2)dnl
