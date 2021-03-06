#!/bin/sh

cd /debathena

touch preseed

pxetype=""

# Using debconf here will hang, so parse the command line manually.
# old options:
#   debathena/clusterforce: implies pxetype=cluster, don't recheck net
#   debathena/clusteraddr: address to use with above
# new options:
#   debathena/pxetype: could be cluster, but could be other things

clusterforce=`sed -e 's/ /\n/g' < /proc/cmdline | grep debathena/clusterforce | sed -e 's/.*=//'`
clusteraddr=`sed -e 's/ /\n/g' < /proc/cmdline | grep debathena/clusteraddr | sed -e 's/.*=//'`
pxetype=`sed -e 's/ /\n/g' < /proc/cmdline | grep debathena/pxetype | sed -e 's/.*=//'`

if [ "$clusteraddr" ] ; then IPADDR=$clusteraddr ; fi
if [ "$clusteraddr" -a "$clusterforce" = yes -a -z "$pxetype" ] ; then pxetype=cluster ; fi

netconfig () {
  echo "Configuring network..."
  mp=/debathena
  export IPADDR NETMASK GATEWAY SYSTEM CONTROL
  while [ -z "$IPADDR" ] ; do
    echo -n "Enter IP address: "
    read IPADDR
  done
  NETMASK=`$mp/athena/netparams -f $mp/athena/masks $IPADDR|cut -d\  -f 1`
  net=`$mp/athena/netparams -f $mp/athena/masks $IPADDR|cut -d\  -f 2`
  bc=`$mp/athena/netparams -f $mp/athena/masks $IPADDR|cut -d\  -f 3`
  GATEWAY=`$mp/athena/netparams -f $mp/athena/masks $IPADDR|cut -d\  -f 4`
  maskbits=`$mp/athena/netparams -f $mp/athena/masks $IPADDR|cut -d\  -f 5`

  echo "Address: $IPADDR"
  echo
  echo "Autoconfigured settings:"
  echo "  Netmask bits: $maskbits"
  echo "  Broadcast: $bc"
  echo "  Gateway: $GATEWAY"

  if [ "$pxetype" != cluster ] ; then
    echo -n "Are these OK? [Y/n]: "; read response
    case $response in
      y|Y|"") ;;
      *) 
      echo -n "Netmask bits [$maskbits]: "; read r; if [ "$r" ] ; then maskbits=$r ; fi
      echo -n "Broadcast [$bc]: "; read r; if [ "$r" ] ; then bc=$r ; fi
      echo -n "Gateway [$GATEWAY]: "; read r; if [ "$r" ] ; then GATEWAY=$r ; fi
    esac
  fi

  # We can not set the hostname here; running "debconf-set netcfg/get_hostname"
  # causes fatal reentry problems.  Setting values directly with preseeding
  # also fails, as the DHCP values override it.
  echo "Killing dhcp client."
  killall dhclient
  echo "Running: ip addr flush dev eth0"
  ip addr flush dev eth0
  echo "Running: ip addr add $IPADDR/$maskbits broadcast $bc dev eth0"
  ip addr add $IPADDR/$maskbits broadcast $bc dev eth0
  echo "Flushing old default route."
  route delete default 2> /dev/null
  echo "Running: route add default gw $GATEWAY"
  route add default gw $GATEWAY
  echo "Replacing installer DHCP nameserver with MIT nameservers."
  sed -e '/nameserver/s/ .*/ 18.72.0.3/' < /etc/resolv.conf > /etc/resolv.conf.new
  echo "nameserver	18.70.0.160" >> /etc/resolv.conf.new
  echo "nameserver	18.71.0.151" >> /etc/resolv.conf.new
  mv -f /etc/resolv.conf.new /etc/resolv.conf
}

# Color strings. I'd like to use tput, but the installer doesn't have it.
esc=""
nnn="${esc}[m"          # Normal
ccc="${esc}[36m"        # Cyan
rrr="${esc}[1;31m"      # Bold and red
ddd="${esc}[1;31;47m"   # Plus gray background
ddb="${esc}[1;31;47;5m" # Plus blinking


echo "Welcome to Athena."
echo

while [ -z "$pxetype" ] ; do
  echo "Choose one:"
  echo
  echo "  1: Perform an unattended ${ccc}debathena-cluster${nnn} install, ${rrr}ERASING your"
  echo "     ENTIRE DISK${nnn}. This option is only intended for people setting up"
  echo "     public cluster machines maintained by IS&T/Athena. If you select"
  echo "     this option, you hereby agree with the license terms at:"
  echo "     <http://dlc.sun.com/dlj/DLJ-v1.1.txt>,"
  echo "     Sun's Operating System Distributor License for Java version 1.1."
  echo
  echo "  2: Do a ${ccc}normal Debathena install${nnn}.  You'll need to answer normal Ubuntu"
  echo "     install prompts, and then the Athena-specific prompts, including"
  echo "     choosing which flavor of Debathena you'd like (e.g., private workstation)."
  echo
  echo "  3: Punt to a completely ${ccc}vanilla install of Ubuntu 10.04${nnn} (Lucid Lynx)."
  echo "     (Note: locale and keyboard have already been set.)"
  echo
  echo "  4: /bin/sh (for rescue purposes)"
  echo
  echo -n "Choose: "
  read r
  case "$r" in
    1)
      echo "Debathena CLUSTER it is."; pxetype=cluster ;;
    1a)
      # Yes, this is undocumented.
      echo "Debathena CLUSTER it is."; pxetype=cluster
      echo -n "...but choose a preferred mirror hostname, too: "
      read mirrorsite
      echo "Using mirror site $mirrorsite";;
    1b)
      # This too.
      echo "Debathena CLUSTER it is."; pxetype=cluster
      echo "...but you get to partition by hand. Your hard disk"
      echo "will not be automatically reformatted."; destroys=notreally
      echo
      echo "The default cluster installer sets up:"
      echo " - a 200MB ext3 /boot partition"
      echo " - an LVM volume group named 'athena', containing"
      echo "   - a (3x system RAM)-sized swap LV (at least 512 MB)"
      echo "   - a root LV taking up half the remaining space (at least 10 GB)"
      echo
      echo "You probably want to set up something similar."
      echo "Press enter to continue."
      read r;;
    2)
      echo "Normal Debathena install it is."; pxetype=choose ;;
    2a)
      echo "Normal Debathena install it is."; pxetype=choose
      echo -n "...but choose a preferred mirror hostname, too: "
      read mirrorsite
      echo "Using mirror site $mirrorsite";;
    3)
      echo "Vanilla Ubuntu it is."; pxetype=vanilla;;
    4)
      echo "Here's a shell.  You'll return to this prompt when done."
      /bin/sh;;
    *)
      echo "Choose one of the above, please.";;
  esac
done

##############################################################################

if [ -z "$mirrorsite" ] ; then mirrorsite=mirrors.mit.edu ; fi

# Consider setting a static IP address, especially if we can't reach the mirror.
if [ cluster != $pxetype ]; then
  # We're at a point in the install process where we can be fairly sure
  # that nothing else is happening, so "killall wget" should be safe.
  (sleep 5; killall wget >/dev/null 2>&1) &
  if wget -s http://$mirrorsite/ubuntu ; then
    if ip address show to 18.0.0.0/8 | grep -q . && ! ip address show to 18.2.0.0/16 | grep -q . ; then
      echo "Your computer seems to be registered on MITnet."
    else
      echo "Your computer seems not to be registered on MITnet, but the mirror"
      echo "site $mirrorsite is accessible."
    fi
    echo
    echo "${ccc}You can continue the install using your existing dynamic address.${nnn}"
    echo -n "Configure a static address anyway?  [y/N]: "
    while : ; do
      read r
      case "$r" in
        N*|n*|"") break;;
        y*|Y*) netconfig; break;;
      esac
      echo -n "Choose: [y/N]: "
    done
  else
    echo "The mirror site $mirrorsite is NOT accessible in your current"
    echo "dynamic configuration."
    echo
    echo "${rrr}You must specify a static address for the installation.${nnn}"
    netconfig
  fi
else
  netconfig
fi

if [ vanilla = $pxetype ] ; then
  echo "Starting normal Ubuntu install in five seconds."
  sleep 5
  exit 0
fi

if [ cluster = "$pxetype" ]; then
  if [ notreally != "$destroys" ]; then
    cat << EOF
************************************************************
               ${ddb}DESTROYS${nnn}
${rrr}THIS PROCEDURE ${ddd}DESTROYS${nnn}${rrr} THE CONTENTS OF THE HARD DISK.${nnn}
               ${ddb}DESTROYS${nnn}

IF YOU DO NOT WISH TO CONTINUE, REBOOT NOW.

************************************************************

EOF
    echo "Installing autoinstall preseed file."
    egrep -v '(^$|^#)' < preseed.autoinstall >> preseed
  else
    echo "Installing autoinstall preseed file without automated partitioning."
    egrep -v '(^$|^#|partman)' < preseed.autoinstall >> preseed
  fi
fi

# Shovel in the generically useful preseed stuff regardless.
egrep -v '(^$|^#)' < preseed.common >> preseed

if [ "$IPADDR" ] ; then
  # ...and the specified network config.
  cat >> preseed <<EOF
d-i netcfg/get_nameservers string 18.72.0.3
d-i netcfg/get_ipaddress string $IPADDR
d-i netcfg/get_netmask string $NETMASK
d-i netcfg/get_gateway string $GATEWAY
d-i netcfg/confirm_static boolean true
EOF
fi

# Perferred hostname of mirror site
cat >> preseed <<EOF
d-i apt-setup/hostname string $mirrorsite
d-i mirror/http/hostname string $mirrorsite
EOF

# This is used by the final installer step.
# A hardcoded number is used as DNS may still be iffy.
echo "Fetching Debathena postinstaller."
# 18.92.2.195 = OLD athena10.mit.edu
# 18.9.60.73 = NEW athena10.mit.edu
wget http://18.9.60.73/install-debathena.sh

# Let the postinstall know what we are up to.
echo "$pxetype" > $mp/pxe-install-flag

echo "Initial Debathena installer complete; exiting preconfig to start main install."
if ! [ "$clusteraddr" -a "$pxetype" = cluster ] ; then
  echo "Hit return to continue."
  read r
fi
exit 0
